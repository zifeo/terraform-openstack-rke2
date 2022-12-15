
resource "null_resource" "agent_remove" {
  count = !var.is_server && var.ff_autoremove_agent ? var.nodes_count : 0

  triggers = {
    agent        = openstack_compute_instance_v2.instance[count.index].id
    name         = openstack_compute_instance_v2.instance[count.index].name
    bastion_host = var.bastion_host
    user         = var.system_user
  }

  connection {
    host    = self.triggers.bastion_host
    user    = self.triggers.user
    agent   = true
    timeout = "30s"
  }

  provisioner "remote-exec" {
    when       = destroy
    on_failure = continue
    inline = [
      "kubectl drain ${lower(self.triggers.name)} --ignore-daemonsets --delete-emptydir-data --timeout=60s; kubectl delete node ${lower(self.triggers.name)}"
    ]
  }

}
