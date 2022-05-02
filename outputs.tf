output "floating_ips" {
  value = flatten([for server in module.servers : server.floating_ips])
}
