locals {
  # on the first server: its cloud-init ends once rke2 runs, rke2.yaml and the API with it. 2 is done with recoverable
  # errors, deprecated keys among them. Through ssh.sh with RERUN=1: a stock image may reboot meanwhile
  wait_for_cloud_init = <<-EOT
    set -eu
    code=0
    timeout 600 cloud-init status --wait >/dev/null || code=$?
    [ "$code" = 0 ] || [ "$code" = 2 ] || { cloud-init status --long; exit 1; }
    systemctl is-active -q rke2-server.service
  EOT
}

# OCCM's credentials as a Secret through the API, which etcd keeps encrypted, never in user_data. Applied again when
# they change, and when the first server's secrets are pushed again: a cluster rebuilt whole, etcd and its Secrets
# lost, rebuilds that server too. Not after every server, which a targeted apply would bring along, replaced at once
resource "terraform_data" "cluster_secrets" {
  triggers_replace = [
    sha256(local.cluster_secrets),
    module.servers[var.servers[0].name].secrets,
  ]

  # a server through the floating IP: the first one during the bootstrap, then whichever holds the VIP. Its cloud-init
  # ends once rke2 runs, and the API with it. Server-side: kubectl's client-side apply copies a Secret whole into an
  # annotation, which describe shows. OCCM reads cloud.conf only when it starts
  provisioner "local-exec" {
    environment = {
      HOST     = local.external_ip
      HOST_KEY = local.servers_host_key.public
      SSH_USER = var.servers[0].system_user
      SECRETS  = local.cluster_secrets
      WAIT     = local.wait_for_cloud_init
      SCRIPT   = <<-EOT
        set -eu
        k="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
        data() { $k -n kube-system get secret "$1" --ignore-not-found -o jsonpath='{.data}'; }
        occm=$(data rke2-occm-cloud-config)
        $k apply --server-side --force-conflicts --field-manager=terraform-openstack-rke2 -f -
        [ -z "$occm" ] || [ "$occm" = "$(data rke2-occm-cloud-config)" ] || $k -n kube-system rollout restart daemonset/openstack-cloud-controller-manager
      EOT
    }
    command = "RERUN=1 bash ${path.module}/node/ssh.sh \"$WAIT\" && printf '%s' \"$SECRETS\" | bash ${path.module}/node/ssh.sh \"$SCRIPT\""
  }
}

resource "null_resource" "wait_for_charts" {
  count = var.ff_wait_ready ? 1 : 0

  triggers = {
    nodes = join(",", flatten([for m in concat(values(module.servers), values(module.agents)) : m.ids]))
  }

  # every node Ready first: CoreDNS and most charts' pods run on the agents, the cloud controller on its Secret
  depends_on = [module.servers, module.agents, terraform_data.cluster_secrets]

  # a chart is installed once the job its HelmChart names has succeeded; none listed yet means none applied yet. The
  # helm controller names each job only once it runs it, so the charts are polled, within 10 minutes
  provisioner "local-exec" {
    environment = {
      HOST     = local.external_ip
      HOST_KEY = local.servers_host_key.public
      SSH_USER = var.servers[0].system_user
      SCRIPT   = <<-EOT
        k="sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"
        for i in $(seq 120); do
          charts=$($k get helmcharts.helm.cattle.io -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}/{.status.jobName}{" "}{end}' 2>/dev/null)
          pending=""
          for c in $charts; do
            ns=$${c%%/*}; rest=$${c#*/}; job=$${rest#*/}
            [ -n "$job" ] && [ "$($k -n "$ns" get job "$job" -o jsonpath='{.status.succeeded}' 2>/dev/null)" = 1 ] || pending="$pending $${rest%%/*}"
          done
          [ -n "$charts" ] && [ -z "$pending" ] && exit 0
          sleep 5
        done
        echo "charts not installed after 10 minutes: $pending" >&2
        exit 1
      EOT
    }
    command = "RERUN=1 bash ${path.module}/node/ssh.sh \"$SCRIPT\""
  }
}
