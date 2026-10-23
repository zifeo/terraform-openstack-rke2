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

variable "image_prebuilt" {
  type = bool
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
  type = string
}

variable "service_cidr" {
  type = string
}

variable "san" {
  type    = list(string)
  default = []
}

variable "secgroup_id" {
  type        = string
  description = "null: no port security"
}

variable "internal_vip" {
  type    = string
  default = ""
}

variable "bastion_host" {
  type = string
}

variable "cinder_credentials" {
  type        = string
  sensitive   = true
  description = "Servers: the [Global] section of Cinder CSI's cloud.conf, pushed with the secrets. null on agents"
  validation {
    condition     = (var.cinder_credentials != null) == var.is_server
    error_message = "Servers need cinder_credentials, agents never get them."
  }
}

variable "vip_port_id" {
  type        = string
  description = "Servers: the VIP's port, which the floating IP is associated with. null on agents"
  validation {
    condition     = (var.vip_port_id != null) == var.is_server
    error_message = "Servers need vip_port_id, agents take none."
  }
}

variable "bastion_user" {
  type        = string
  description = "The servers' system user, which the bastion is reached as"
}

variable "bastion_host_key" {
  type        = string
  description = "The servers' SSH host key, which the bastion presents whichever server it reaches"
}

variable "nodeport_cidr" {
  type        = string
  description = "Where kube-proxy serves node ports, when it runs: the agents' subnet"
}

variable "host_key" {
  type = object({
    private = string
    public  = string
  })
  sensitive   = true
  default     = null
  description = "Servers: the SSH host key they share, so that tofu can pin the bastion. null: one key per node"
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

variable "rke2_agent_token" {
  type        = string
  default     = null
  description = "Servers only: the token agents join with."
  validation {
    condition     = var.is_server == (var.rke2_agent_token != null)
    error_message = "rke2_agent_token is for servers, and only them."
  }
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

# without the restore key, which the conversion to this type drops: whoever takes a node cannot read the snapshots
variable "s3" {
  type = object({
    endpoint      = string
    access_key    = string
    access_secret = string
    bucket        = string
    region        = optional(string)
    # null: as many as etcd-snapshot-retention
    retention = optional(number)
  })
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

variable "agent_removal_timeout" {
  type = string
}

variable "ff_wait_ready" {
  type    = bool
  default = false
}

variable "kube_proxy" {
  type = bool
}

variable "ff_gateway_api_crd" {
  type = bool
}

variable "node_taints" {
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string
  }))
}

variable "node_labels" {
  type = map(string)
}

variable "registries" {
  type = object({
    mirrors = optional(map(object({
      endpoint = list(string)
      rewrite  = optional(map(string))
    })))
    configs = optional(map(object({
      auth = optional(object({
        username : optional(string)
        password : optional(string)
        token : optional(string)
      }))
      tls = optional(object({
        ca_file : optional(string)
        cert_file : optional(string)
        key_file : optional(string)
        insecure_skip_verify : optional(bool)
      }))
    })))
  })

  default = null
}

variable "runtime_classes" {
  type = map(object({
    handler      = string
    runtime_type = string
    options      = map(string)
  }))
}

variable "gpu" {
  type = object({
    enabled = optional(bool, false)
    driver = optional(object({
      package      = optional(string, "nvidia-driver-580")
      version      = optional(string) # apt pin, e.g. "580.178.04-0ubuntu0.26.04.1"
      preinstalled = optional(bool, false)
    }), {})
    toolkit_package = optional(string, "nvidia-container-toolkit")
    toolkit_version = optional(string) # apt pin for toolkit_package when set
    runtime_class   = optional(bool, true)
  })
  default = {
    enabled         = false
    driver          = {}
    toolkit_package = "nvidia-container-toolkit"
    runtime_class   = true
  }
  description = "Optional NVIDIA GPU setup for agent nodes. Installs driver/toolkit, registers the nvidia containerd runtime, and can deploy a RuntimeClass. Workloads must set runtimeClassName: nvidia. Pin apt versions with driver.version / toolkit_version when needed."
}

variable "firewall" {
  type = list(object({
    protocol = string
    port     = string
    from     = string
  }))
  description = "What UFW lets in (../firewall): protocol tcp, udp or any, port a number, a range a:b or any, a source CIDR"
}

variable "kubelet_config" {
  type = string
}
