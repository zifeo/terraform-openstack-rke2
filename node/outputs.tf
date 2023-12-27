
output "first_id" {
  value = openstack_compute_instance_v2.instance[0].id
}

output "ids" {
  value = openstack_compute_instance_v2.instance[*].id
}
