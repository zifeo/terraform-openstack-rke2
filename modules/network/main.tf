
resource "openstack_networking_network_v2" "net" {
  name                  = "${var.name}-net"
  admin_state_up        = "true"
  port_security_enabled = "true"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name       = "${var.name}-subnet"
  network_id = openstack_networking_network_v2.net.id
  cidr              = var.cidr
  ip_version        = var.ip_version
  dns_nameservers   = var.dns_nameservers
  ipv6_address_mode = "dhcpv6-stateful"
  ipv6_ra_mode      = "dhcpv6-stateful"
}

data "openstack_networking_network_v2" "external_net" {
  name = var.external_net
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.name}-router"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.external_net.id
}

resource "openstack_networking_router_interface_v2" "interface" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}
