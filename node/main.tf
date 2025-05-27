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

  name               = "${var.name}-${count.index + 1}"
  network_id         = var.network_id
  security_group_ids = [var.secgroup_id]

  fixed_ip {
    subnet_id = var.subnet_id
  }

  dynamic "allowed_address_pairs" {
    for_each = var.is_server ? [var.internal_vip] : []
    content {
      ip_address = allowed_address_pairs.value
    }
  }
}

resource "openstack_compute_instance_v2" "instance" {
  count                   = var.nodes_count
  name                    = "${var.name}-${count.index + 1}"
  availability_zone_hints = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  flavor_name  = var.flavor_name
  key_pair     = var.keypair_name
  config_drive = true

  network {
    port = openstack_networking_port_v2.port[count.index].id
  }

  scheduler_hints {
    group = var.group_id
  }

  metadata = {
    rke2_version = var.rke2_version
    rke2_role    = var.is_server ? "server" : "agent"
  }

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

  # yamlencode(yamldecode to debug yaml
  user_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    rke2_token    = var.rke2_token
    rke2_version  = var.rke2_version
    rke2_conf     = var.rke2_config != null ? var.rke2_config : ""
    rke2_device   = var.rke2_volume_device
    is_server     = var.is_server
    is_first      = var.is_first && count.index == 0
    bootstrap     = var.bootstrap && var.is_first && count.index == 0
    internal_vip  = var.internal_vip
    vip_interface = var.vip_interface
    node_ip       = openstack_networking_port_v2.port[count.index].all_fixed_ips[0]
    cluster_cidr  = var.cluster_cidr
    service_cidr  = var.service_cidr
    cni           = var.cni
    san           = var.is_server ? var.san : []
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
    system_user        = var.system_user
    authorized_keys    = var.ssh_authorized_keys
    ff_wait_apiserver  = false
    ff_with_kubeproxy  = var.ff_with_kubeproxy
    node_taints  = var.node_taints
    node_labels  = var.node_labels
  }))
}

/*
resource "local_file" "debug" {
  count    = var.nodes_count
  filename = "${path.module}/${var.name}-${count.index + 1}.yaml"
  content = ""
}
*/
