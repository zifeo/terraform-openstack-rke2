output "floating_ips" {
  value = openstack_networking_floatingip_v2.floating_ip[*].address
}

output "internal_ips" {
  value = openstack_compute_instance_v2.instance[*].access_ip_v4
}

output "id" {
  value = openstack_compute_instance_v2.instance[*].id
}
