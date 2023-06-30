locals {
  s3 = var.ff_native_backup && var.object_store_endpoint != "" ? {
    endpoint      = var.object_store_endpoint
    access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots[0].name
  } : var.s3_backup

  external_ip      = openstack_networking_floatingip_v2.external.address
  internal_ip      = var.lb_internal_ip != null ? var.lb_internal_ip : cidrhost(var.subnet_lb_cidr, 4)
  operator_replica = length(var.servers) > 1 ? 2 : 1
}

module "servers" {
  source = "./node"

  for_each = {
    for server in var.servers :
    server.name => server
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = true
  is_first     = var.servers[0].name == each.value.name
  is_persisted = length(var.servers) == 1
  bootstrap    = var.bootstrap

  nodes_count      = 1
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size
  boot_volume_type = each.value.boot_volume_type

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_string.rke2_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  s3 = local.s3

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id   = openstack_networking_network_v2.net.id
  subnet_id    = openstack_networking_subnet_v2.servers.id
  secgroup_id  = openstack_networking_secgroup_v2.server.id
  bootstrap_ip = local.internal_ip
  bastion_host = local.external_ip
  san          = [local.internal_ip, local.external_ip]

  manifests_folder = var.manifests_folder
  manifests = merge(
    {
      "cinder-csi.yml" : templatefile("${path.module}/manifests/csi-cinder.yml.tpl", {
        operator_replica = local.operator_replica
        auth_url         = var.identity_endpoint
        region           = openstack_identity_application_credential_v3.rke2.region
        project_id       = openstack_identity_application_credential_v3.rke2.project_id
        app_id           = openstack_identity_application_credential_v3.rke2.id
        app_secret       = openstack_identity_application_credential_v3.rke2.secret
        app_name         = openstack_identity_application_credential_v3.rke2.name
      }),
      "velero.yml" : templatefile("${path.module}/manifests/velero.yml.tpl", {
        auth_url      = var.identity_endpoint
        region        = openstack_identity_application_credential_v3.rke2.region
        app_id        = openstack_identity_application_credential_v3.rke2.id
        app_secret    = openstack_identity_application_credential_v3.rke2.secret
        app_name      = openstack_identity_application_credential_v3.rke2.name
        bucket_restic = openstack_objectstorage_container_v1.restic.name
        bucket_velero = openstack_objectstorage_container_v1.velero.name
      }),
      "cloud-controller-openstack.yml" : templatefile("${path.module}/manifests/cloud-controller-openstack.yml.tpl", {
        auth_url            = var.identity_endpoint
        region              = openstack_identity_application_credential_v3.rke2.region
        project_id          = openstack_identity_application_credential_v3.rke2.project_id
        app_id              = openstack_identity_application_credential_v3.rke2.id
        app_secret          = openstack_identity_application_credential_v3.rke2.secret
        app_name            = openstack_identity_application_credential_v3.rke2.name
        network_id          = openstack_networking_network_v2.net.id
        subnet_id           = openstack_networking_subnet_v2.lb.id
        floating_network_id = data.openstack_networking_network_v2.floating_net.id
        lb_provider         = var.lb_provider
        cluster_name        = var.name
      }),
      "cilium.yml" : templatefile("${path.module}/manifests/cilium.yml.tpl", {
        operator_replica = local.operator_replica
        apiserver_host   = local.internal_ip
        cluster_name     = var.name
        cluster_id       = var.cluster_id
      }),
      "ha.yml" : templatefile("${path.module}/manifests/ha.yml.tpl", {
        operator_replica = local.operator_replica
      }),
    },
    {
      for f in fileset(path.module, "manifests/*.{yml,yaml}") : basename(f) => file("${path.module}/${f}")
    },
    var.manifests,
  )

  ff_autoremove_agent = false

  depends_on = [
    openstack_lb_listener_v2.k8s,
    openstack_lb_listener_v2.rke2,
  ]
}

module "agents" {
  source = "./node"

  for_each = {
    for agent in var.agents :
    agent.name => agent
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = false
  is_first     = false
  is_persisted = false
  bootstrap    = false

  nodes_count      = each.value.nodes_count
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size
  boot_volume_type = each.value.boot_volume_type

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_string.rke2_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id   = openstack_networking_network_v2.net.id
  subnet_id    = openstack_networking_subnet_v2.agents.id
  secgroup_id  = openstack_networking_secgroup_v2.agent.id
  bootstrap_ip = local.internal_ip
  bastion_host = local.external_ip

  ff_autoremove_agent = var.ff_autoremove_agent

  depends_on = [
    openstack_lb_listener_v2.k8s,
    openstack_lb_listener_v2.rke2,
  ]
}
