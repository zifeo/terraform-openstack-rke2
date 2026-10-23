# What a node gets over SSH before rke2 starts, without any resource: its user_data, which Nova keeps and serves to
# anything that reaches the metadata, holds none of it. tests/cloud-init renders it too, so that the e2e pushes the same.

variable "token" {
  type        = string
  sensitive   = true
  description = "Servers: the cluster's token. Agents: the agents' token"
}

variable "agent_token" {
  type        = string
  sensitive   = true
  description = "Servers: what agents join with. null on agents"
}

variable "s3" {
  type = object({
    access_key    = string
    access_secret = string
  })
  sensitive   = true
  description = "The etcd snapshots' upload key, on servers. null without snapshots in an object store, and on agents"
}

variable "cinder_credentials" {
  type        = string
  sensitive   = true
  description = "Servers: the [Global] section of Cinder CSI's cloud.conf. null on agents"
}

variable "registries" {
  type        = any
  sensitive   = true
  description = "The module's registries input, whose configs may hold credentials. null for none"
}

locals {
  # what the Cinder CSI node plugin reads (cinder-csi-plugin 1.37 in nova attach mode: [BlockStorage] and [Metadata]
  # only, no OpenStack client); the controller, on the servers, needs the credentials too. The instance ID from the
  # config drive: the nodes do not reach the metadata service
  cinder_block_storage = <<-EOT
    [BlockStorage]
    ignore-volume-az = true
    rescan-on-resize = true
    [Metadata]
    search-order = configDrive
  EOT
}

# /etc/rancher/rke2/config.yaml.d/50-secrets.yaml, which cloud-init waits for before it starts rke2. The token goes
# apart (../hooks.tf), prefixed at push time with the hash of rke2's own CA
output "config" {
  value = yamlencode(merge(
    var.agent_token != null ? { "agent-token" = var.agent_token } : {},
    var.s3 != null ? { "etcd-s3-access-key" = var.s3.access_key, "etcd-s3-secret-key" = var.s3.access_secret } : {},
  ))
  sensitive = true
}

output "token" {
  value     = var.token
  sensitive = true
}

# /etc/config/cloud.conf of a server, which the chart mounts from the node (hostMount)
output "cinder" {
  value     = var.cinder_credentials != null ? "${var.cinder_credentials}${local.cinder_block_storage}" : null
  sensitive = true
}

# /etc/config/cloud.conf of an agent, in its user_data: no credential, so that no agent holds one
output "cinder_node" {
  value = local.cinder_block_storage
}

# /etc/rancher/rke2/registries.yaml, pushed before the config: rke2 reads it once, when it starts
output "registries" {
  value     = var.registries != null ? yamlencode(var.registries) : yamlencode({})
  sensitive = true
}
