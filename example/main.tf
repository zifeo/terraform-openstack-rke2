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

  public_net_name = "ext-floating1"
  # 22 & 6443 should be restricted to a secure bastion
  rules_ext = [
    { "port" : 22, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 80, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 6443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
  ]

  server = {
    nodes_count = 1

    flavor_name      = "a1-ram2-disk0"
    image_name       = "Ubuntu 20.04 LTS Focal Fossa"
    system_user      = "ubuntu"
    boot_volume_size = 4

    rke2_version     = "v1.21.5+rke2r1"
    rke2_volume_size = 6
    # https://docs.rke2.io/install/install_options/install_options/#configuration-file
    rke2_config_file = "configs/server.yaml"
  }

  agents = [
    {
      name        = "pool-a"
      nodes_count = 1

      flavor_name      = "a1-ram2-disk0"
      image_name       = "Ubuntu 20.04 LTS Focal Fossa"
      system_user      = "ubuntu"
      boot_volume_size = 4

      rke2_version     = "v1.21.5+rke2r2"
      rke2_volume_size = 6
    }
  ]

  # etcd snapshots (https://docs.rke2.io/backup_restore/)
  s3 = {
    endpoint      = "s3.pub1.infomaniak.cloud"
    access_key    = openstack_identity_ec2_credential_v3.s3.access
    access_secret = openstack_identity_ec2_credential_v3.s3.secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots.name
  }

  # rke2 manifest autoload (https://docs.rke2.io/helm/)
  manifests_folder = "./manifests"
  manifests = {
    "cinder-csi-plugin.yml" : templatefile("${path.root}/configs/cinder.yml.tpl", {
      auth_url   = local.auth_url
      region     = local.region
      project_id = openstack_identity_application_credential_v3.rke2_csi.project_id
      app_id     = openstack_identity_application_credential_v3.rke2_csi.id
      app_secret = openstack_identity_application_credential_v3.rke2_csi.secret
    })
  }

  # enable automatically `kubectl delete node AGENT-NAME` after an agent change
  ff_autoremove_agent = true
}

resource "openstack_identity_application_credential_v3" "rke2_csi" {
  name = "${local.name}-csi-credentials"
}

resource "openstack_objectstorage_container_v1" "etcd_snapshots" {
  name          = "${local.name}-etcd-snapshots"
  force_destroy = true
}

resource "openstack_identity_ec2_credential_v3" "s3" {}
