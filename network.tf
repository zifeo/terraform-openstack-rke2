data "openstack_networking_network_v2" "public_net" {
  name = var.floating_ip_net
}

resource "openstack_networking_network_v2" "nodes_net" {
  name                  = "${var.name}-nodes-net"
  admin_state_up        = "true"
  port_security_enabled = "true"
}

resource "openstack_networking_subnet_v2" "nodes_subnet" {
  name            = "${var.name}-nodes-subnet"
  network_id      = openstack_networking_network_v2.nodes_net.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
}

resource "openstack_networking_router_v2" "nodes_router" {
  name                = "${var.name}-router-nodes"
  admin_state_up      = true
  external_network_id = data.openstack_networking_network_v2.public_net.id
}

resource "openstack_networking_router_interface_v2" "nodes_router_interface" {
  router_id = openstack_networking_router_v2.nodes_router.id
  subnet_id = openstack_networking_subnet_v2.nodes_subnet.id
}

module "net_server" {
  source = "./modules/network"

  external_net    = var.external_net_name
  name            = "${var.name}-server"
  ip_version      = 6
  cidr            = "2001:1600:11:70::/64"
  dns_nameservers = ["2606:4700:4700::1111", "2606:4700:4700::1001"]
}

###

module "net_traffic" {
  source = "./modules/network"

  external_net    = var.external_net_name
  name            = "${var.name}-traffic"
  ip_version      = 6
  cidr            = "2001:1600:11:71::/64"
  dns_nameservers = ["2606:4700:4700::1111", "2606:4700:4700::1001"]
}
