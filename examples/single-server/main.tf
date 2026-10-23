module "rke2" {
  # source = "zifeo/rke2/openstack"
  # version = ""
  source = "./../.."

  name                = "single-server"
  ssh_authorized_keys = ["~/.ssh/id_rsa.pub"]
  floating_pool       = "ext-floating1"
  # should be restricted to a secure bastion
  rules_ssh_cidr = ["0.0.0.0/0"]
  rules_k8s_cidr = ["0.0.0.0/0"]
  # auto load manifest form a folder (https://docs.rke2.io/advanced#auto-deploying-manifests)
  manifests_folder = "./manifests"

  servers = [{
    name = "server-a"

    flavor_name = "a2-ram4-disk0"
    image_name  = "Ubuntu 26.04 LTS Resolute Raccoon"
    # if you want fixed image version
    # image_uuid       = "UUID"

    system_user      = "ubuntu"
    boot_volume_size = 6

    rke2_version     = "v1.37.1+rke2r1"
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
      image_name  = "Ubuntu 26.04 LTS Resolute Raccoon"
      # if you want fixed image version
      # image_uuid       = "UUID"

      system_user      = "ubuntu"
      boot_volume_size = 6

      rke2_version     = "v1.37.1+rke2r1"
      rke2_volume_size = 8
    }
  ]

  backup_schedule  = "0 6 1 * *" # once a month
  backup_retention = 20

  kube_apiserver_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_scheduler_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  kube_controller_manager_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  etcd_resources = {
    requests = {
      cpu    = "75m"
      memory = "128M"
    }
  }

  # drain and delete the Node of a destroyed agent (wait max 30s for SSH)
  agent_removal_timeout = "30s"
  # rewrite kubeconfig
  ff_write_kubeconfig = true
  # deploy etcd backup
  etcd_snapshots_in_object_store = true
  # wait for the cluster to be ready when deploying
  ff_wait_ready = true

  identity_endpoint     = "https://api.pub1.infomaniak.cloud/identity"
  object_store_endpoint = "s3.pub1.infomaniak.cloud"
}

output "cluster" {
  value     = module.rke2
  sensitive = true
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
  required_version = ">= 1.10"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }
}
