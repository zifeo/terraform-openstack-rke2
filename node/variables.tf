variable "name" {
  type = string
}

variable "is_server" {
  type = bool
}

variable "is_first" {
  type = bool
}

variable "is_persisted" {
  type = bool
}

variable "bootstrap" {
  type = bool
}

variable "nodes_count" {
  type = string
}

variable "flavor_name" {
  type = string
}

variable "image_name" {
  type = string
}

variable "image_uuid" {
  type    = string
  default = null
}

variable "boot_volume_size" {
  type = number
}

variable "boot_volume_type" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

variable "group_id" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "cluster_cidr" {
  type    = string
}

variable "service_cidr" {
  type    = string
}

variable "cni" {
  type    = string
}

variable "san" {
  type    = list(string)
  default = []
}

variable "secgroup_id" {
  type = string
}

variable "internal_vip" {
  type    = string
  default = ""
}

variable "vip_interface" {
  type = string
}

variable "bastion_host" {
  type = string
}

variable "system_user" {
  type = string
}

variable "keypair_name" {
  type = string
}

variable "rke2_version" {
  type = string
}

variable "rke2_config" {
  type = string
}

variable "rke2_token" {
  type = string
}

variable "rke2_volume_size" {
  type = number
}

variable "rke2_volume_type" {
  type = string
}

variable "rke2_volume_device" {
  type     = string
  default  = "/dev/sdb"
  nullable = false
}

variable "backup_schedule" {
  type    = string
  default = null
}

variable "backup_retention" {
  type    = number
  default = null
}

variable "s3" {
  type = object({
    endpoint      = string
    access_key    = string
    access_secret = string
    bucket        = string
  })
  default = {
    endpoint      = ""
    access_key    = ""
    access_secret = ""
    bucket        = ""
  }
}

variable "kube_apiserver_resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = null
}

variable "kube_scheduler_resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = null
}

variable "kube_controller_manager_resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = null
}

variable "etcd_resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = null
}

variable "kube_proxy_resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
    limits = optional(object({
      cpu    = optional(string)
      memory = optional(string)
    }))
  })
  default = null
}

variable "manifests_folder" {
  type    = string
  default = ""
}

variable "manifests" {
  type    = map(string)
  default = {}
}

variable "ssh_authorized_keys" {
  type = list(string)
}

variable "ff_autoremove_agent" {
  type = string
}

variable "ff_wait_ready" {
  type    = bool
  default = false
}

variable "ff_with_kubeproxy" {
  type = bool
}

variable "node_taints" {
  type = map(string)
}

variable "node_labels" {
  type    = map(string)
} 