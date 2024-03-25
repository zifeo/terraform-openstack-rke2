
variable "name" {
  type = string
}

variable "ssh_authorized_keys" {
  type    = list(string)
  default = ["~/.ssh/id_rsa.pub"]
}

variable "floating_pool" {
  type = string
}

variable "rules_ssh_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.rules_ssh_cidr)) || var.rules_ssh_cidr == null
    error_message = "Must be a valid IPv4 CIDR block or null (no access)"
  }
}

variable "rules_k8s_cidr" {
  type = string
  validation {
    condition     = can(cidrnetmask(var.rules_k8s_cidr)) || var.rules_k8s_cidr == null
    error_message = "Must be a valid IPv4 CIDR block or null (no access)"
  }
}

variable "rules_server_server" {
  type = list(object({
    port     = number
    protocol = string
    name     = optional(string)
  }))
  default = []
}

variable "rules_server_agent" {
  type = list(object({
    port     = number
    protocol = string
    name     = optional(string)
  }))
  default = []
}

variable "rules_agent_server" {
  type = list(object({
    port     = number
    protocol = string
    name     = optional(string)
  }))
  default = []
}

variable "rules_agent_agent" {
  type = list(object({
    port     = number
    protocol = string
    name     = optional(string)
  }))
  default = []
}

variable "subnet_servers_cidr" {
  type    = string
  default = "192.168.42.0/24"
}

variable "subnet_servers_vip" {
  type    = string
  default = null
}

variable "subnet_agents_cidr" {
  type    = string
  default = "192.168.43.0/24"
}

variable "subnet_lb_cidr" {
  type    = string
  default = "192.168.44.0/24"
}

variable "dns_nameservers4" {
  type = list(string)
  # Cloudflare
  default = ["1.1.1.1", "1.0.0.1"]
}

variable "lb_provider" {
  type     = string
  default  = "amphora"
  nullable = false
}

variable "additional_san" {
  type    = list(string)
  default = []
}

variable "bootstrap" {
  type    = bool
  default = false
}

variable "servers" {
  type = list(object({
    name               = string
    group_id           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    image_uuid         = optional(string)
    system_user        = string
    boot_volume_size   = number
    boot_volume_type   = optional(string)
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
    rke2_volume_type   = optional(string)
    rke2_volume_device = optional(string)
  }))
  validation {
    condition = (
      length(var.servers) % 2 == 1
    )
    error_message = "RKE requires an odd number of servers"
  }
  validation {
    condition = (
      length(toset(var.servers[*].name)) == length(var.servers[*].name)
    )
    error_message = "server nodes must have unique names"
  }
}

variable "agents" {
  type = list(object({
    name               = string
    nodes_count        = number
    group_id           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    image_uuid         = optional(string)
    system_user        = string
    boot_volume_size   = number
    boot_volume_type   = optional(string)
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
    rke2_volume_type   = optional(string)
    rke2_volume_device = optional(string)
  }))
  validation {
    condition = (
      length(toset(var.agents[*].name)) == length(var.agents[*].name)
    )
    error_message = "agent nodes must have unique names"
  }
}

variable "s3_backup" {
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

variable "backup_schedule" {
  type    = string
  default = null
}

variable "backup_retention" {
  type    = number
  default = null
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

variable "manifests_folder" {
  type    = string
  default = ""
}

variable "manifests" {
  type    = map(string)
  default = {}
}

variable "cluster_id" {
  type    = number
  default = 0
}

variable "object_store_endpoint" {
  type    = string
  default = ""
}

variable "identity_endpoint" {
  type = string
}

variable "ff_write_kubeconfig" {
  type    = bool
  default = true
}

variable "ff_autoremove_agent" {
  type    = string
  default = null
}

variable "ff_native_backup" {
  type    = bool
  default = true
}

variable "ff_wait_ready" {
  type    = bool
  default = true
}
