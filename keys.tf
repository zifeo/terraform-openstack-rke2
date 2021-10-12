resource "random_string" "rke2_token" {
  length = 64
}

resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.name}-key"
  public_key = file(var.ssh_public_key_file)
}

resource "null_resource" "write_kubeconfig" {
  triggers = {
    servers = join(",", module.server.id)
  }

  connection {
    host  = module.server.floating_ips[0]
    user  = var.server.system_user
    agent = true
  }

  provisioner "remote-exec" {
    inline = ["until (grep rke2 /etc/rancher/rke2/rke2-remote.yaml >/dev/null 2>&1); do echo Waiting for $(hostname) rke2 to start && sleep 10; done;"]
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ${var.server.system_user}@${module.server.floating_ips[0]}:/etc/rancher/rke2/rke2-remote.yaml rke2.yaml"
  }
}
