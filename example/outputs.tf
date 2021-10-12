output "floating_ip" {
  value = module.rke2.floating_ips[0]
}
