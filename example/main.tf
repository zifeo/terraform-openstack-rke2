locals {
  auth_url = "https://api.pub1.infomaniak.cloud/identity"
  region   = "dc3-a"
  config   = <<EOF
# https://docs.rke2.io/install/install_options/install_options/#configuration-file
# https://docs.rke2.io/install/install_options/server_config/
node-taint:
  - "CriticalAddonsOnly=true:NoExecute"

etcd-snapshot-schedule-cron: "* */6 * * *"
etcd-snapshot-retention: 20

control-plane-resource-requests: kube-apiserver-cpu=75m,kube-apiserver-memory=128M,kube-scheduler-cpu=75m,kube-scheduler-memory=128M,kube-controller-manager-cpu=75m,kube-controller-manager-memory=128M,kube-proxy-cpu=75m,kube-proxy-memory=128M,etcd-cpu=75m,etcd-memory=128M,cloud-controller-manager-cpu=75m,cloud-controller-manager-memory=128M
  EOF
}

provider "openstack" {
  auth_url = local.auth_url
  region   = local.region
}

module "rke2" {
  # source = "zifeo/rke2/openstack"
  source = "./.."

  name = "cluster"
  # rke2 manifest autoload (https://docs.rke2.io/helm/)
  manifests_folder = "./manifests"

  floating_pool = "ext-floating1"
  # 22 & 6443 should be restricted to a secure bastion
  rules_ext = [
    { "port" : 22, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 80, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 6443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
  ]

  server = [{
    name = "server"

    flavor_name      = "a1-ram2-disk0"
    image_name       = "Ubuntu 22.04 LTS Jammy Jellyfish"
    system_user      = "ubuntu"
    boot_volume_size = 4

    rke2_version     = "v1.25.3+rke2r1"
    rke2_volume_size = 6
    # https://docs.rke2.io/install/install_options/install_options/#configuration-file
    rke2_config = local.config
  }]

  agents = [
    {
      name        = "pool-a"
      nodes_count = 1

      flavor_name      = "a1-ram2-disk0"
      image_name       = "Ubuntu 22.04 LTS Jammy Jellyfish"
      system_user      = "ubuntu"
      boot_volume_size = 4

      rke2_version     = "v1.25.3+rke2r1"
      rke2_volume_size = 6
    }
  ]

  # deploy cinder csi
  ff_native_csi = local.auth_url
  # enable automatically `kubectl delete node AGENT-NAME` after an agent change
  ff_autoremove_agent = true
  # rewrite kubeconfig
  ff_write_kubeconfig = true
  # deploy etcd backup
  ff_native_backup = "s3.pub1.infomaniak.cloud"
}

output "floating_ip" {
  value = module.rke2.floating_ips[0]
}

terraform {
  required_version = ">= 0.14.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.44.0"
    }
  }
}
