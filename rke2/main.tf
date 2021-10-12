module "server" {
  source    = "./node"
  name      = "${var.name}-server"
  is_server = true

  nodes_count      = var.server.nodes_count
  flavor_name      = var.server.flavor_name
  image_name       = var.server.image_name
  boot_volume_size = var.server.boot_volume_size

  availability_zones = coalesce(var.server.availability_zones, [])
  affinity           = coalesce(var.server.affinity, "soft-anti-affinity")

  rke2_version     = var.server.rke2_version
  rke2_config_file = var.server.rke2_config_file
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = var.server.rke2_volume_size

  s3 = var.s3

  system_user  = var.server.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.nodes_net.id
  subnet_id        = openstack_networking_subnet_v2.nodes_subnet.id
  secgroup_id      = openstack_networking_secgroup_v2.server.id
  bootstrap_server = var.bootstrap_server
  floating_ip_net  = var.public_net_name

  manifests_folder = var.manifests_folder
  manifests        = var.manifests
}

module "agents" {
  source = "./node"

  for_each = {
    for agent in var.agents :
    agent.name => agent
  }

  name      = "${var.name}-${each.value.name}"
  is_server = false

  nodes_count      = each.value.nodes_count
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  boot_volume_size = each.value.boot_volume_size

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version     = each.value.rke2_version
  rke2_config_file = each.value.rke2_config_file
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = each.value.rke2_volume_size

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.nodes_net.id
  subnet_id        = openstack_networking_subnet_v2.nodes_subnet.id
  secgroup_id      = openstack_networking_secgroup_v2.agent.id
  bootstrap_server = var.bootstrap_server
  bastion_host     = module.server.floating_ips[0]
}
