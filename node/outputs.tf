# the pushes: what references them comes once the node has its secrets, and again when it is rebuilt
output "secrets" {
  value = terraform_data.secrets[*].id
}

output "ids" {
  value = openstack_compute_instance_v2.instance[*].id
}

output "ssh_hosts" {
  value = {
    for i, instance in openstack_compute_instance_v2.instance : instance.name => {
      address = openstack_networking_port_v2.port[i].all_fixed_ips[0]
      user    = var.system_user
      # public, though derived from the private key
      host_key = nonsensitive(local.host_keys[i].public)
    }
  }
}
