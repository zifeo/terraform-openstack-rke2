module "rke2" {
  # source = "zifeo/rke2/openstack"
  # version = ""
  source = "./../.."

  # must be true for single server cluster or
  # only on the first run for high-availability cluster 
  bootstrap           = true
  name                = "single-server"
  ssh_authorized_keys = ["~/.ssh/id_rsa.pub"]
  floating_pool       = "ext-floating1"
  # should be restricted to a secure bastion
  rules_ssh_cidr = "0.0.0.0/0"
  rules_k8s_cidr = "0.0.0.0/0"
  # auto load manifest form a folder (https://docs.rke2.io/advanced#auto-deploying-manifests)
  manifests_folder = "./manifests"

  servers = [{
    name = "server-a"

    flavor_name = "a2-ram4-disk0"
    image_name  = "Ubuntu 22.04 LTS Jammy Jellyfish"
    # if you want fixed image version
    # image_uuid       = "UUID"
    image_uuid = "8ca95333-e5c3-4d9b-90bc-f261ca434114"

    system_user      = "ubuntu"
    boot_volume_size = 8

    rke2_version     = "v1.28.4+rke2r1"
    rke2_volume_size = 8
    # https://docs.rke2.io/install/install_options/server_config/
    rke2_config = <<EOF
# https://docs.rke2.io/install/install_options/server_config/
EOF
    }
  ]

  agents = [
    {
      name        = "pool"
      nodes_count = 1

      flavor_name = "a1-ram2-disk0"
      image_name  = "Ubuntu 22.04 LTS Jammy Jellyfish"
      # if you want fixed image version
      # image_uuid       = "UUID"
      image_uuid = "8ca95333-e5c3-4d9b-90bc-f261ca434114"

      system_user      = "ubuntu"
      boot_volume_size = 8

      rke2_version     = "v1.28.4+rke2r1"
      rke2_volume_size = 8
    }
  ]

  backup_schedule  = "0 */6 * * *"
  backup_retention = 20

  kube-apiserver-resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube-scheduler-resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube-controller-manager-resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  etcd-resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  # enable automatically agent removal of the cluster (wait max for 30s)
  ff_autoremove_agent = "30s"
  # rewrite kubeconfig
  ff_write_kubeconfig = true
  # deploy etcd backup
  ff_native_backup = true

  identity_endpoint     = "https://api.pub1.infomaniak.cloud/identity"
  object_store_endpoint = "s3.pub1.infomaniak.cloud"
}

output "restore_cmd" {
  value     = module.rke2.restore_cmd
  sensitive = true
}

output "ip" {
  value = module.rke2.external_ip
}

variable "project" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

provider "openstack" {
  tenant_name = var.project
  user_name   = var.username
  # checkov:skip=CKV_OPENSTACK_1
  password = var.password
  auth_url = "https://api.pub1.infomaniak.cloud/identity"
  region   = "dc3-a"
}

terraform {
  required_version = ">= 0.14.0"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.53.0"
    }
  }
}
