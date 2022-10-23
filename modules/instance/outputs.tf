output "external_ips" {
  value = locals.external_ips
}

output "floating_ips" {
  value = locals.floating_ips
}

output "internal_ips" {
  value = openstack_compute_instance_v2.instance[*].access_ip_v4
}

output "id" {
  value = openstack_compute_instance_v2.instance[*].id
}
