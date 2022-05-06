
output "net_id" {
  value = openstack_networking_network_v2.net.id
}

output "net_name" {
  value = openstack_networking_network_v2.net.name
}

output "subnet_id" {
  value = openstack_networking_subnet_v2.subnet.id
}
