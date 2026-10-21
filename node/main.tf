locals {
  host_keys = [for i in range(var.nodes_count) : var.host_key != null ? var.host_key : {
    private = tls_private_key.host[i].private_key_openssh
    public  = trimspace(tls_private_key.host[i].public_key_openssh)
  }]
}

data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

resource "openstack_blockstorage_volume_v3" "volume" {
  count                = var.is_persisted ? var.nodes_count : 0
  name                 = "${var.name}-${count.index + 1}-rke2"
  size                 = var.rke2_volume_size
  volume_type          = var.rke2_volume_type
  enable_online_resize = true
}

resource "openstack_networking_port_v2" "port" {
  count = var.nodes_count

  name                  = "${var.name}-${count.index + 1}"
  network_id            = var.network_id
  security_group_ids    = var.secgroup_id == null ? [] : [var.secgroup_id]
  no_security_groups    = var.secgroup_id == null ? true : null
  port_security_enabled = var.secgroup_id == null ? false : null

  fixed_ip {
    subnet_id = var.subnet_id
  }

  # without port security nothing filters the VIP, and Neutron refuses address pairs
  dynamic "allowed_address_pairs" {
    for_each = var.is_server && var.secgroup_id != null ? [var.internal_vip] : []
    content {
      ip_address = allowed_address_pairs.value
    }
  }
}

module "metadata" {
  source = "./metadata"
  count  = var.nodes_count

  rke2_version        = var.rke2_version
  role                = var.is_server ? "server" : "agent"
  bootstrap           = var.bootstrap && var.is_first && count.index == 0
  ssh_authorized_keys = var.ssh_authorized_keys
  firewall            = var.firewall
}

# agents' own host keys: servers share theirs (var.host_key)
resource "tls_private_key" "host" {
  count     = var.host_key == null ? var.nodes_count : 0
  algorithm = "ED25519"
}

module "secrets" {
  source = "./secrets"

  token              = var.rke2_token
  agent_token        = var.rke2_agent_token
  s3                 = var.s3 == null ? null : { access_key = var.s3.access_key, access_secret = var.s3.access_secret }
  cinder_credentials = var.cinder_credentials
  registries         = var.registries
}

resource "openstack_compute_instance_v2" "instance" {
  count                   = var.nodes_count
  name                    = "${var.name}-${count.index + 1}"
  availability_zone_hints = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  flavor_name  = var.flavor_name
  key_pair     = var.keypair_name
  config_drive = true
  # Nova deletes an instance at once otherwise: stopped first, its kubelet's graceful shutdown and
  # rke2-static-pods-cleanup run before it goes
  stop_before_destroy = true

  network {
    port = openstack_networking_port_v2.port[count.index].id
  }

  scheduler_hints {
    group = var.group_id
  }

  metadata = module.metadata[count.index].metadata

  block_device {
    uuid                  = var.image_uuid != null ? var.image_uuid : data.openstack_images_image_v2.image.id
    source_type           = "image"
    volume_size           = var.boot_volume_size
    volume_type           = var.boot_volume_type
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  block_device {
    uuid                  = var.is_persisted ? openstack_blockstorage_volume_v3.volume[count.index].id : null
    source_type           = var.is_persisted ? "volume" : "blank"
    boot_index            = 1
    destination_type      = "volume"
    volume_size           = var.is_persisted ? null : var.rke2_volume_size
    volume_type           = var.is_persisted ? null : var.rke2_volume_type
    delete_on_termination = var.is_persisted ? false : true
    # currently, you cannot enable online resize and delete_on_termination
    # this requires 2 apply per node (1 pass to delete the server, 1 pass to create the server)
    # https://github.com/terraform-provider-openstack/terraform-provider-openstack/issues/1545
    # potential solution: https://github.com/hashicorp/terraform/issues/31707
  }

  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    # a prebuilt image already has the packages and their upgrades
    image_prebuilt     = var.image_prebuilt
    node_config_script = file("${path.module}/rke2-node-config.py")
    kubelet_config     = var.kubelet_config
    host_key           = local.host_keys[count.index]
    rke2_version       = var.rke2_version
    rke2_conf          = var.rke2_config != null ? var.rke2_config : ""
    rke2_device        = var.rke2_volume_device
    is_server          = var.is_server
    secrets_sha256     = nonsensitive(sha256(join("", [module.secrets.token, module.secrets.config, module.secrets.registries, module.secrets.cinder != null ? module.secrets.cinder : ""])))
    cinder_node        = module.secrets.cinder_node
    is_first           = var.is_first && count.index == 0
    internal_vip       = var.internal_vip
    node_ip            = openstack_networking_port_v2.port[count.index].all_fixed_ips[0]
    cluster_cidr       = var.cluster_cidr
    service_cidr       = var.service_cidr
    san                = var.is_server ? var.san : []
    manifests_files = var.is_server ? merge(
      var.manifests_folder != "" ? {
        for f in fileset(var.manifests_folder, "*.{yml,yaml}") : f => base64gzip(file("${var.manifests_folder}/${f}"))
      } : {},
      { for k, v in var.manifests : k => base64gzip(v) },
    ) : {}
    s3               = var.s3
    backup_schedule  = var.backup_schedule
    backup_retention = var.backup_retention
    control_plane_requests = join(",", [for limit in [
      try("kube-apiserver-cpu=${var.kube_apiserver_resources.requests.cpu}", ""),
      try("kube-apiserver-memory=${var.kube_apiserver_resources.requests.memory}", ""),
      try("kube-scheduler-cpu=${var.kube_scheduler_resources.requests.cpu}", ""),
      try("kube-scheduler-memory=${var.kube_scheduler_resources.requests.memory}", ""),
      try("kube-controller-manager-cpu=${var.kube_controller_manager_resources.requests.cpu}", ""),
      try("kube-controller-manager-memory=${var.kube_controller_manager_resources.requests.memory}", ""),
      try("etcd-cpu=${var.etcd_resources.requests.cpu}", ""),
      try("etcd-memory=${var.etcd_resources.requests.memory}", ""),
      try("kube-proxy-cpu=${var.kube_proxy_resources.requests.cpu}", ""),
      try("kube-proxy-memory=${var.kube_proxy_resources.requests.memory}", ""),
    ] : limit if limit != ""])
    control_plane_limits = join(",", [for limit in [
      try("kube-apiserver-cpu=${var.kube_apiserver_resources.limits.cpu}", ""),
      try("kube-apiserver-memory=${var.kube_apiserver_resources.limits.memory}", ""),
      try("kube-scheduler-cpu=${var.kube_scheduler_resources.limits.cpu}", ""),
      try("kube-scheduler-memory=${var.kube_scheduler_resources.limits.memory}", ""),
      try("kube-controller-manager-cpu=${var.kube_controller_manager_resources.limits.cpu}", ""),
      try("kube-controller-manager-memory=${var.kube_controller_manager_resources.limits.memory}", ""),
      try("etcd-cpu=${var.etcd_resources.limits.cpu}", ""),
      try("etcd-memory=${var.etcd_resources.limits.memory}", ""),
      try("kube-proxy-cpu=${var.kube_proxy_resources.limits.cpu}", ""),
      try("kube-proxy-memory=${var.kube_proxy_resources.limits.memory}", ""),
    ] : limit if limit != ""])
    system_user             = var.system_user
    customize_chart_script  = base64gzip(file("${path.module}/customize-chart.sh"))
    customize_charts_script = base64gzip(file("${path.module}/customize-charts.sh"))
    kube_proxy              = var.kube_proxy
    nodeport_cidr           = var.nodeport_cidr
    node_taints             = [for t in var.node_taints : "${t.key}${t.value != null ? "=${t.value}" : ""}:${t.effect}"]
    node_labels             = var.node_labels
    gpu                     = var.gpu
    runtime_classes         = values(var.runtime_classes)
    ff_gateway_api_crd      = var.ff_gateway_api_crd
  }))
}

