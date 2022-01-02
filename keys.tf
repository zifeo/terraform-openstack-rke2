resource "random_string" "rke2_token" {
  length = 64
}

resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.name}-key"
  public_key = file(var.ssh_public_key_file)
}

resource "null_resource" "write_kubeconfig" {
  count = var.ff_write_kubeconfig ? 1 : 0

  triggers = {
    servers = join(",", module.server.id)
  }

  depends_on = [
    module.server[0].id
  ]

  connection {
    host  = module.server.floating_ips[0]
    user  = var.server.system_user
    agent = true
  }

  provisioner "local-exec" {
    command = <<EOF
      ssh-keygen -F ${module.server.floating_ips[0]} -f ~/.ssh/known_hosts | grep -q found || ssh-keyscan ${module.server.floating_ips[0]} >> ~/.ssh/known_hosts 2>/dev/null
      rsync --rsync-path="sudo rsync" ${var.server.system_user}@${module.server.floating_ips[0]}:/etc/rancher/rke2/rke2.yaml rke2.yaml
      chmod go-r rke2.yaml
      yq eval --inplace '.clusters[0].name = "${var.name}-cluster"' rke2.yaml
      yq eval --inplace '.clusters[0].cluster.server = "https://${module.server.floating_ips[0]}:6443"' rke2.yaml
      yq eval --inplace '.users[0].name = "${var.name}-user"' rke2.yaml
      yq eval --inplace '.contexts[0].context.cluster = "${var.name}-cluster"' rke2.yaml
      yq eval --inplace '.contexts[0].context.user = "${var.name}-user"' rke2.yaml
      yq eval --inplace '.contexts[0].name = "${var.name}"' rke2.yaml
      yq eval --inplace '.current-context = "${var.name}"' rke2.yaml
    EOF
  }
}
