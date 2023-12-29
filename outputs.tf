output "external_ip" {
  value = local.external_ip
}

output "network_id" {
  value = openstack_networking_network_v2.net.id
}

output "lb_subnet_id" {
  value = openstack_networking_subnet_v2.lb.id
}

output "restore_cmd" {
  value     = "sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=${local.s3.bucket} --etcd-s3-access-key=${local.s3.access_key} --etcd-s3-secret-key=${local.s3.access_secret} --cluster-reset-restore-path=[filename]"
  sensitive = true
}

output "ssh_cmd" {
  value     = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=accept-new -o ForwardAgent=yes ubuntu@${local.external_ip}"
  sensitive = true
}


output "ssh_config" {
  value     = <<EOF
Host ${var.name}
HostName ${local.external_ip}
Port 22
User ubuntu
ForwardAgent yes
UserKnownHostsFile /dev/null
StrictHostKeyChecking accept-new
  EOF
  sensitive = true
}
