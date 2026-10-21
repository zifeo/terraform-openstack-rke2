locals {
  rke2_service = var.is_server ? "rke2-server.service" : "rke2-agent.service"
  # the first server, made without server: (cloud-init.yaml.tpl), joins through the VIP once bootstrap is false
  join = [for i in range(var.nodes_count) : var.is_first && i == 0 && !var.bootstrap ? "server: \"https://${var.internal_vip}:9345\"\n" : ""]
  # the node that starts the cluster makes its CA: every other checks it on joining, its token prefixed with the hash
  bootstraps = [for i in range(var.nodes_count) : var.bootstrap && var.is_first && i == 0]
  # how tofu reaches the node: through the floating IP, each hop's host key checked (ssh.sh)
  ssh = [for i in range(var.nodes_count) : {
    BASTION      = var.bastion_host
    BASTION_KEY  = var.bastion_host_key
    BASTION_USER = var.bastion_user
    HOST         = openstack_compute_instance_v2.instance[i].access_ip_v4
    HOST_KEY     = local.host_keys[i].public
    SSH_USER     = var.system_user
  }]
}

resource "null_resource" "agent_remove" {
  count = !var.is_server && var.agent_removal_timeout != null ? var.nodes_count : 0

  triggers = {
    agent        = openstack_compute_instance_v2.instance[count.index].id
    name         = openstack_compute_instance_v2.instance[count.index].name
    bastion_host = var.bastion_host
    bastion_key  = var.bastion_host_key
    user         = var.bastion_user
    timeout      = var.agent_removal_timeout
  }

  connection {
    host     = self.triggers.bastion_host
    host_key = self.triggers.bastion_key
    user     = self.triggers.user
    agent    = true
    timeout  = self.triggers.timeout
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

# what rke2 needs and user_data never holds, the config last: cloud-init starts rke2 once it is there, and each file
# lands whole (mv). rke2 reads them only when it starts: their digest in user_data replaces the node when they change.
# The node's SSH keys and firewall come first, and again in place when they change, applied at once once cloud-init is
# through. Before the cluster exists, the first server holds the VIP the floating IP reaches it through (network.tf)
resource "terraform_data" "secrets" {
  count = var.nodes_count

  triggers_replace = [
    openstack_compute_instance_v2.instance[count.index].id,
    local.join[count.index],
    sha256(module.metadata[count.index].config),
  ]

  provisioner "local-exec" {
    environment = merge(local.ssh[count.index], {
      NODE       = module.metadata[count.index].config
      TOKEN      = module.secrets.token
      TOKEN_USER = var.is_server ? "server" : "node"
      BOOTSTRAPS = local.bootstraps[count.index] ? "1" : ""
      JOIN       = local.join[count.index]
      CINDER     = module.secrets.cinder != null ? module.secrets.cinder : ""
      REGISTRIES = module.secrets.registries
      CONFIG     = module.secrets.config
    })
    command = <<-EOT
      set -eu
      # folder, file, content: again when the node reboots under it (cloud-init's package_reboot_if_required)
      push() {
        for attempt in 1 2 3; do
          code=0
          printf '%s' "$3" | bash ${path.module}/ssh.sh "sudo sh -c 'umask 077 && mkdir -p $1 && cat > $1/.$2 && mv $1/.$2 $1/$2'" || code=$?
          [ "$code" = 255 ] || return "$code"
          sleep 10
        done
        return 255
      }
      push /etc/rancher rke2-node-config.json "$NODE"
      [ -z "$CINDER" ] || push /etc/config cloud.conf "$CINDER"
      [ -z "$JOIN" ] || push /etc/rancher/rke2/config.yaml.d 40-join.yaml "$JOIN"
      push /etc/rancher/rke2 registries.yaml "$REGISTRIES"
      # the hash of rke2's CA, which the bastion, a server, writes in its token once rke2 runs, waited for as long as
      # cloud-init waits for these secrets: rke2 makes and renews the CA, a node joining checks it
      # (K10<hash>::<user>:<password>), and nothing of it lives here
      token=$TOKEN
      if [ -z "$BOOTSTRAPS" ]; then
        ca=$(HOST=$BASTION HOST_KEY=$BASTION_KEY SSH_USER=$BASTION_USER BASTION= RERUN=1 bash ${path.module}/ssh.sh \
          "timeout 1800 cloud-init status --wait >/dev/null; sudo cat /var/lib/rancher/rke2/server/token" | sed -n 's/^K10\([0-9a-f]\{64\}\)::.*/\1/p')
        [ "$${#ca}" = 64 ] || { echo "no CA hash in the token of $BASTION" >&2; exit 1; }
        token="K10$ca::$TOKEN_USER:$TOKEN"
      fi
      push /etc/rancher/rke2/config.yaml.d 49-token.yaml "token: \"$token\""
      push /etc/rancher/rke2/config.yaml.d 50-secrets.yaml "$CONFIG"
      # before, cloud-init applies it once the secrets are there
      RERUN=1 bash ${path.module}/ssh.sh "[ ! -e /var/lib/cloud/instance/boot-finished ] || sudo systemctl start rke2-node-config.service"
    EOT
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

  depends_on = [terraform_data.secrets]

  provisioner "local-exec" {
    environment = merge(local.ssh[count.index], {
      SCRIPT = <<-EOT
        set -eu
        # cloud-init's last step waits for rke2: 2 is done with recoverable errors, deprecated keys among them
        code=0
        timeout 600 cloud-init status --wait >/dev/null || code=$?
        [ "$code" = 0 ] || [ "$code" = 2 ] || { cloud-init status --long; exit 1; }
        systemctl is-active -q ${local.rke2_service} || { systemctl status --no-pager ${local.rke2_service} | tail -n 20; exit 1; }
        # rke2 is active long before its kubelet registers and Cilium readies the node: the kubelet's own credentials
        # watch its Node, on agents too
        k="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /var/lib/rancher/rke2/agent/kubelet.kubeconfig"
        node="node/$(hostname | tr A-Z a-z)"
        $k wait --for=create "$node" --timeout=300s
        $k wait --for=condition=Ready "$node" --timeout=300s
      EOT
    })
    command = "RERUN=1 bash ${path.module}/ssh.sh \"$SCRIPT\""
  }
}
