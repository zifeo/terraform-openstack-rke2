resource "openstack_networking_network_v2" "net" {
  name                  = "${var.name}-net"
  port_security_enabled = "true"
}

resource "openstack_networking_subnet_v2" "servers" {
  name            = "${var.name}-servers-subnet"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.subnet_servers_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers4
}

resource "openstack_networking_subnet_v2" "agents" {
  name            = "${var.name}-agents-subnet"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.subnet_agents_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers4
}

resource "openstack_networking_subnet_v2" "lb" {
  name            = "${var.name}-lb-subnet"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.subnet_lb_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers4
}

data "openstack_networking_network_v2" "floating_net" {
  name = var.floating_pool
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.name}-router"
  external_network_id = data.openstack_networking_network_v2.floating_net.id
}

resource "openstack_networking_router_interface_v2" "servers" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.servers.id
}

resource "openstack_networking_router_interface_v2" "agents" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.agents.id
}

resource "openstack_networking_router_interface_v2" "lb" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.lb.id
}

resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool        = var.floating_pool
  description = "FIP for ${var.name}-vip (used)"
}

resource "openstack_networking_floatingip_associate_v2" "fip" {
  floating_ip = openstack_networking_floatingip_v2.floating_ip.address
  port_id     = openstack_networking_port_v2.dummy.id
}

resource "openstack_networking_port_v2" "dummy" {
  # this port enables the fip to be associated dynamically via allowed_address_pairs
  # if associated directly to a server, it will steal the ip without being ready
  name               = "${var.name}-vip"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.server.id]
  admin_state_up     = false

  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.servers.id
    ip_address = local.internal_vip
  }
}
