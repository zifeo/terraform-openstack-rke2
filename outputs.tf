output "floating_ips" {
  value = flatten([for server in module.servers : server.floating_ips])
}

output "restore_cmd" {
  value     = "rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=${local.s3.bucket} --etcd-s3-access-key=${local.s3.access_key} --etcd-s3-secret-key=${local.s3.access_secret} --cluster-reset-restore-path="
  sensitive = true
}
