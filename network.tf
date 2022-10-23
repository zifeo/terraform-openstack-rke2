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

resource "openstack_networking_subnet_v2" "servers-ext" {
  name       = "${var.name}-servers-subnet-ext"
  network_id = openstack_networking_network_v2.servers.id
  cidr       = var.external_cidr
  #subnetpool_id     = "a7c19bf9-37a9-4355-b47d-e5d9f24c3d1b"
  ip_version        = var.external_ip_version
  dns_nameservers   = var.external_ip_version == 6 ? var.dns_nameservers6 : var.dns_nameservers4
  ipv6_address_mode = var.external_ip_version == 6 ? "dhcpv6-stateful" : null
  ipv6_ra_mode      = var.external_ip_version == 6 ? "dhcpv6-stateful" : null
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

data "openstack_networking_network_v2" "external_net" {
  name = var.external_net_name
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external_net.id
}

resource "openstack_networking_router_interface_v2" "servers-ext" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.servers-ext.id
}

resource "openstack_networking_router_interface_v2" "servers" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.servers.id
}

resource "openstack_networking_router_interface_v2" "agents" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.agents.id
}

