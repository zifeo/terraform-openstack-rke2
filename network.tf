resource "openstack_networking_network_v2" "servers" {
  name                  = "${var.name}-servers-net"
  admin_state_up        = "true"
  port_security_enabled = "true"
}

resource "openstack_networking_subnet_v2" "servers" {
  name            = "${var.name}-servers-subnet"
  network_id      = openstack_networking_network_v2.servers.id
  cidr            = var.subnet_servers_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers4
}

resource "openstack_networking_network_v2" "agents" {
  name                  = "${var.name}-agents-net"
  admin_state_up        = "true"
  port_security_enabled = "true"
}

resource "openstack_networking_subnet_v2" "agents" {
  name            = "${var.name}-agents-subnet"
  network_id      = openstack_networking_network_v2.agents.id
  cidr            = var.subnet_agents_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers4
}

data "openstack_networking_network_v2" "floating_net" {
  count = var.floating_pool != "" ? 1 : 0

  name = var.floating_pool
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.name}-router"
  admin_state_up      = true
  external_network_id = var.floating_pool != "" ? data.openstack_networking_network_v2.floating_net[0].id : null
}

resource "openstack_networking_router_interface_v2" "servers" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.servers.id
}

resource "openstack_networking_router_interface_v2" "agents" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.agents.id
}

resource "openstack_networking_floatingip_v2" "floating_ip" {
  pool    = var.floating_pool
  port_id = openstack_networking_port_v2.port.id
}

resource "openstack_networking_port_v2" "port" {
  network_id         = openstack_networking_network_v2.servers.id
  no_security_groups = true
  admin_state_up     = true

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.servers.id
  }
}
