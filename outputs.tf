output "external_ip" {
  value = local.external_ip
}

output "outgoing_ip" {
  value = openstack_networking_router_v2.router.external_fixed_ip[0].ip_address
}

output "network_id" {
  value = openstack_networking_network_v2.net.id
}

output "servers_subnet_id" {
  value = openstack_networking_subnet_v2.servers.id
}

output "lb_subnet_id" {
  value = try(openstack_networking_subnet_v2.lb[0].id, null)
}

output "agents_subnet_id" {
  value = openstack_networking_subnet_v2.agents.id
}

output "restore_cmd" {
  value     = local.s3 == null ? null : "sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=${local.s3.bucket} --etcd-s3-access-key=${local.s3.restore_access_key} --etcd-s3-secret-key=${local.s3.restore_access_secret} --cluster-reset-restore-path=[filename]"
  sensitive = true
}

# the host keys tofu made, which ssh checks without a known_hosts file to keep
output "ssh_cmd" {
  value     = "ssh -o UserKnownHostsFile=/dev/null -o 'KnownHostsCommand=/bin/echo %H ${local.servers_host_key.public}' -o StrictHostKeyChecking=yes ${var.servers[0].system_user}@${local.external_ip}"
  sensitive = true
}

# each node through the floating IP: ProxyJump, unlike a forwarded agent, lends root on the jump host no key
output "ssh_config" {
  value     = <<EOF
Host ${var.name}
HostName ${local.external_ip}
Port 22
User ${var.servers[0].system_user}
UserKnownHostsFile /dev/null
KnownHostsCommand /bin/echo %H ${local.servers_host_key.public}
StrictHostKeyChecking yes
%{for name, host in merge([for m in concat(values(module.servers), values(module.agents)) : m.ssh_hosts]...)~}
Host ${name}
HostName ${host.address}
User ${host.user}
ProxyJump ${var.name}
UserKnownHostsFile /dev/null
KnownHostsCommand /bin/echo %H ${host.host_key}
StrictHostKeyChecking yes
%{endfor~}
  EOF
  sensitive = true
}
