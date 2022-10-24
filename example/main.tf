locals {
  auth_url = "https://api.pub1.infomaniak.cloud/identity"
  region   = "dc3-a"
  name     = "k8s"
}

provider "openstack" {
  tenant_name = var.tenant_name
  user_name   = var.user_name
  password    = var.password
  auth_url    = local.auth_url
  region      = local.region
}

module "rke2" {
  # source = "zifeo/rke2/openstack"
  source = "./.."

  name = local.name

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
    image_name       = "Ubuntu 20.04 LTS Focal Fossa"
    system_user      = "ubuntu"
    boot_volume_size = 4

    rke2_version     = "v1.25.3+rke2r1"
    rke2_volume_size = 6
    # https://docs.rke2.io/install/install_options/install_options/#configuration-file
    rke2_config = file("server.yaml")
  }]

  agents = [
    {
      name        = "pool-a"
      nodes_count = 1

      flavor_name      = "a1-ram2-disk0"
      image_name       = "Ubuntu 20.04 LTS Focal Fossa"
      system_user      = "ubuntu"
      boot_volume_size = 4

      rke2_version     = "v1.25.3+rke2r1"
      rke2_volume_size = 6
    }
  ]

  # rke2 manifest autoload (https://docs.rke2.io/helm/)
  manifests_folder = "./manifests"

  # deploy cinder csi
  ff_native_csi = "https://api.pub1.infomaniak.cloud/identity"
  # enable automatically `kubectl delete node AGENT-NAME` after an agent change
  ff_autoremove_agent = true
  # rewrite kubeconfig
  ff_write_kubeconfig = true
  # deploy etcd backup
  ff_native_backup = "s3.pub1.infomaniak.cloud"
}
