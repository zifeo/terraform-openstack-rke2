locals {
  s3 = var.ff_native_backup != "" ? {
    endpoint      = var.ff_native_backup
    access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots[0].name
  } : var.s3_backup

  proxy_ips = var.floating_pool != "" ? module.servers[0].floating_ips : module.servers[0].external_ips
  proxy_ip  = local.proxy_ips[0]
}

module "servers" {
  source = "./modules/instance"

  for_each = {
    for server in var.servers :
    index(var.servers, server) => server
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = true
  is_bootstrap = each.key == "0"

  nodes_count      = 1
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version     = each.value.rke2_version
  rke2_config      = each.value.rke2_config
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = each.value.rke2_volume_size

  s3 = local.s3

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.servers.id
  subnet_id        = openstack_networking_subnet_v2.servers.id
  secgroup_id      = openstack_networking_secgroup_v2.server.id
  bootstrap_server = var.bootstrap_server
  floating_pool    = var.floating_pool

  manifests_folder = var.manifests_folder
  manifests = merge(
    var.manifests,
    var.ff_native_csi != "" ? {
      "cinder-csi-plugin.yml" : templatefile("${path.module}/templates/cinder.yml.tpl", {
        auth_url   = var.ff_native_csi
        region     = openstack_identity_application_credential_v3.rke2_csi[0].region
        project_id = openstack_identity_application_credential_v3.rke2_csi[0].project_id
        app_id     = openstack_identity_application_credential_v3.rke2_csi[0].id
        app_secret = openstack_identity_application_credential_v3.rke2_csi[0].secret
    }) } : {},
    var.ff_snapshot_controller ? templatefile("${path.module}/templates/snapshot-controller.yml.tpl", {}) : {},
    var.ff_snapshot_controller ? templatefile("${path.module}/templates/snapshot-validation-webhook.yml.tpl", {}) : {}
  )
  ff_autoremove_agent = var.ff_autoremove_agent
}

module "agents" {
  source = "./modules/instance"

  for_each = {
    for agent in var.agents :
    index(var.agents, agent) => agent
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = false
  is_bootstrap = false

  nodes_count      = each.value.nodes_count
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version     = each.value.rke2_version
  rke2_config      = each.value.rke2_config
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = each.value.rke2_volume_size

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.agents.id
  subnet_id        = openstack_networking_subnet_v2.agents.id
  secgroup_id      = openstack_networking_secgroup_v2.agent.id
  bootstrap_server = var.bootstrap_server
  bastion_host     = local.proxy_ip

  ff_autoremove_agent = var.ff_autoremove_agent
}
