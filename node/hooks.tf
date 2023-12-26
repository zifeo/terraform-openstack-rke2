resource "null_resource" "agent_remove" {
  count = !var.is_server && var.ff_autoremove_agent != null ? var.nodes_count : 0

  triggers = {
    agent        = openstack_compute_instance_v2.instance[count.index].id
    name         = openstack_compute_instance_v2.instance[count.index].name
    bastion_host = var.bastion_host
    user         = var.system_user
    timeout      = var.ff_autoremove_agent != null ? var.ff_autoremove_agent : "never happens"
  }

  connection {
    host    = self.triggers.bastion_host
    user    = self.triggers.user
    agent   = true
    timeout = self.triggers.timeout
  }

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml drain ${lower(self.triggers.name)} --ignore-daemonsets --delete-emptydir-data --timeout=60s || true",
      "sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml delete node ${lower(self.triggers.name)}"
    ]
  }
}

resource "null_resource" "wait_for_rke2" {
  count = var.ff_wait_ready ? var.nodes_count : 0
  triggers = {
    agent        = openstack_compute_instance_v2.instance[count.index].id
    host         = openstack_compute_instance_v2.instance[count.index].access_ip_v4
    bastion_host = var.bastion_host
    user         = var.system_user
  }

  connection {
    bastion_host = var.is_server ? null : self.triggers.bastion_host
    bastion_user = var.is_server ? null : self.triggers.user
    host         = self.triggers.host
    user         = self.triggers.user
    agent        = true
    timeout      = "3m"
  }

  provisioner "remote-exec" {
    on_failure = continue
    inline = [
      "test \"$(sudo systemctl is-active ${var.is_server ? "rke2-server.service" : "rke2-agent.service"})\" = active"
    ]
  }
}
