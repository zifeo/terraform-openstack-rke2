output "names" {
  value = openstack_compute_instance_v2.instance[*].name

}
output "internal_ips" {
  value = openstack_compute_instance_v2.instance[*].access_ip_v4
}

output "id" {
  value = openstack_compute_instance_v2.instance[*].id
}

output "first_id" {
  value = openstack_compute_instance_v2.instance[0].id
}
