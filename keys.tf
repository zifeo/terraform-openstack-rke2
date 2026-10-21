locals {
  ssh_authorized_keys_loaded = [for key in var.ssh_authorized_keys : startswith(key, "/") || startswith(key, "~") ? file(key) : key]
  ssh_authorized_key         = local.ssh_authorized_keys_loaded[0]
  ssh_authorized_keys        = slice(local.ssh_authorized_keys_loaded, 1, length(local.ssh_authorized_keys_loaded))
  servers_host_key = {
    private = tls_private_key.servers_host.private_key_openssh
    public  = trimspace(tls_private_key.servers_host.public_key_openssh)
  }
}

# a password, so that plans and applies never print it (see the v6 migration for clusters that had a random_string)
resource "random_password" "rke2_token" {
  length = 64
}

# what agents join with: root on an agent does not get the servers' token, which gives the cluster's CA
resource "random_password" "rke2_agent_token" {
  length  = 64
  special = false
}

# the servers' SSH host key: the floating IP reaches whichever server holds the VIP, so they share the one tofu pins
resource "tls_private_key" "servers_host" {
  algorithm = "ED25519"
}

resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.name}-key"
  public_key = local.ssh_authorized_key
}

resource "null_resource" "write_kubeconfig" {
  count = var.ff_write_kubeconfig ? 1 : 0

  triggers = {
    servers = join(",", flatten([for server in module.servers : server.ids]))
  }

  depends_on = [module.servers]

  provisioner "local-exec" {
    environment = {
      HOST     = local.external_ip
      HOST_KEY = local.servers_host_key.public
      SSH_USER = var.servers[0].system_user
      WAIT     = local.wait_for_cloud_init
    }
    command = <<-EOT
      set -eu
      umask 077
      RERUN=1 bash ${path.module}/node/ssh.sh "$WAIT"
      bash ${path.module}/node/ssh.sh 'sudo cat /etc/rancher/rke2/rke2.yaml' > rke2.yaml
      yq eval --inplace '.clusters[0].name = "${var.name}-cluster"' rke2.yaml
      yq eval --inplace '.clusters[0].cluster.server = "https://${local.external_ip}:6443"' rke2.yaml
      yq eval --inplace '.users[0].name = "${var.name}-user"' rke2.yaml
      yq eval --inplace '.contexts[0].context.cluster = "${var.name}-cluster"' rke2.yaml
      yq eval --inplace '.contexts[0].context.user = "${var.name}-user"' rke2.yaml
      yq eval --inplace '.contexts[0].name = "${var.name}"' rke2.yaml
      yq eval --inplace '.current-context = "${var.name}"' rke2.yaml
      mv rke2.yaml ${var.name}.rke2.yaml
    EOT
  }
}

resource "openstack_identity_application_credential_v3" "rke2" {
  name = "${var.name}-credentials"
}

