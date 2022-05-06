module "servers" {
  source = "./modules/instance"

  for_each = {
    for server in var.servers :
    index(var.servers, server) => server
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = true
  is_bootstrap = each.key == "0"

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

  s3 = var.s3

  nets = [{
    network_name = module.net_server.net_name
    network_id   = module.net_server.net_id
    subnet_id    = module.net_server.subnet_id
    secgroup_id  = openstack_networking_secgroup_v2.server.id
    ip_address   = null
  }]

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.nodes_net.id
  subnet_id        = openstack_networking_subnet_v2.nodes_subnet.id
  secgroup_id      = openstack_networking_secgroup_v2.server.id
  bootstrap_server = var.bootstrap_server
  floating_ip_net  = each.key == "0" ? var.floating_ip_net : null

  manifests_folder = var.manifests_folder
  manifests = merge(var.manifests, var.cinder.manifest_file != "" ? {
    "cinder-csi-plugin.yml" : templatefile("${path.module}/${var.cinder.manifest_file}", {
      auth_url   = var.identity_url
      region     = openstack_identity_application_credential_v3.rke2_csi.region
      project_id = openstack_identity_application_credential_v3.rke2_csi.project_id
      app_id     = openstack_identity_application_credential_v3.rke2_csi.id
      app_secret = openstack_identity_application_credential_v3.rke2_csi.secret
  }) } : {})

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

  network_id       = openstack_networking_network_v2.nodes_net.id
  subnet_id        = openstack_networking_subnet_v2.nodes_subnet.id
  secgroup_id      = openstack_networking_secgroup_v2.agent.id
  bootstrap_server = var.bootstrap_server
  bastion_host     = module.servers[0].floating_ips[0]

  ff_autoremove_agent = var.ff_autoremove_agent
}
