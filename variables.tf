
variable "name" {
  type = string
}

variable "ssh_authorized_keys" {
  type        = list(string)
  default     = []
  description = "The first is the instances' keypair; tofu pushes the others over SSH, so changing them replaces no node."
}

variable "floating_pool" {
  type = string
}

variable "rules_ssh_cidr" {
  type        = list(string)
  description = "Where SSH to the servers comes from: tofu's own, which pushes the nodes' secrets through the floating IP, included."
  validation {
    condition     = var.rules_ssh_cidr != null && length(coalesce(var.rules_ssh_cidr, [])) > 0 && alltrue([for r in coalesce(var.rules_ssh_cidr, []) : can(cidrnetmask(r))])
    error_message = "Must be a non-empty list of IPv4 CIDRs including where tofu runs: it reaches every node by SSH."
  }
}

variable "rules_k8s_cidr" {
  type = list(string)
  validation {
    condition     = var.rules_k8s_cidr == null ? true : alltrue([for r in var.rules_k8s_cidr : can(cidrnetmask(r))])
    error_message = "Must be a valid IPv4 CIDR list or null (no access)"
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

variable "cluster_cidr" {
  type    = string
  default = "10.42.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.43.0.0/16"
}

variable "dns_nameservers4" {
  type = list(string)
  # Quad9, run by a Swiss foundation: validates DNSSEC and blocks malware domains
  default = ["9.9.9.9", "149.112.112.112"]
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
  type        = bool
  default     = null
  description = "Several servers: true while the first one starts the cluster alone, false once it runs (that server gets its join, nothing replaced). A single server takes none: it always runs the cluster alone."
  validation {
    condition     = (length(var.servers) == 1) == (var.bootstrap == null)
    error_message = "Set bootstrap with several servers, and only then: a single server always starts the cluster alone."
  }
}

variable "ff_grow_from_single_server" {
  type        = bool
  default     = false
  description = "While a single server becomes several (README): the first keeps its rke2 volume, so its cluster survives. Drop it once the others run."
  validation {
    condition     = !var.ff_grow_from_single_server || length(var.servers) > 1
    error_message = "ff_grow_from_single_server is for a single server becoming several."
  }
}

variable "servers" {
  type = list(object({
    name               = string
    group_id           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    image_uuid         = optional(string)
    image_prebuilt     = optional(bool, false)
    system_user        = string
    boot_volume_size   = number
    boot_volume_type   = optional(string)
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
    rke2_volume_type   = optional(string)
    rke2_volume_device = optional(string)
    node_taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    node_labels = optional(map(string), {})
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
  validation {
    condition     = alltrue([for s in var.servers : alltrue([for t in s.node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])])
    error_message = "The taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
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
    image_prebuilt     = optional(bool, false)
    system_user        = string
    boot_volume_size   = number
    boot_volume_type   = optional(string)
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
    rke2_volume_type   = optional(string)
    rke2_volume_device = optional(string)
    node_taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])
    node_labels = optional(map(string), {})
    gpu = optional(object({
      enabled = optional(bool, false)
      driver = optional(object({
        package      = optional(string, "nvidia-driver-580")
        version      = optional(string)
        preinstalled = optional(bool, false)
      }), {})
      toolkit_package = optional(string, "nvidia-container-toolkit")
      toolkit_version = optional(string)
      runtime_class   = optional(bool, true)
    }), {})
    runtime_classes = optional(map(object({
      handler      = string
      runtime_type = string
      options      = optional(map(string), {})
    })), {})
  }))
  validation {
    condition = (
      length(toset(var.agents[*].name)) == length(var.agents[*].name)
    )
    error_message = "agent nodes must have unique names"
  }
  validation {
    condition     = alltrue([for a in var.agents : length(a.runtime_classes) == 0 || length(a.node_labels) > 0])
    error_message = "An agent pool with runtime_classes needs node_labels: its RuntimeClasses select its nodes with them."
  }
  validation {
    condition = (
      length(distinct(flatten([for a in var.agents : keys(a.runtime_classes)]))) == length(flatten([for a in var.agents : keys(a.runtime_classes)]))
      && !contains(flatten([for a in var.agents : keys(a.runtime_classes)]), "nvidia")
    )
    error_message = "RuntimeClass names must be unique across agent pools, and nvidia is the GPU one."
  }
  validation {
    condition = alltrue(flatten([for a in var.agents : [
      length(distinct([for rc in values(a.runtime_classes) : rc.handler])) == length(a.runtime_classes),
      [for rc in values(a.runtime_classes) : concat(
        [can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", rc.handler))],
        [for k in keys(rc.options) : can(regex("^[A-Za-z0-9_-]+$", k))],
      )],
    ]]))
    error_message = "The runtime_classes handlers of a pool must be distinct DNS labels, and their option names bare TOML keys."
  }
  validation {
    condition     = alltrue([for a in var.agents : alltrue([for t in a.node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)])])
    error_message = "The taint effect must be one of: NoSchedule, PreferNoSchedule, NoExecute."
  }
  validation {
    # CoreDNS runs on untainted agents only (main.tf's agent_replica)
    condition     = sum(concat([0], [for a in var.agents : a.nodes_count if length(a.node_taints) == 0])) >= 1
    error_message = "CoreDNS runs on the agents only: at least one agent node without taints."
  }
}

variable "s3_backup" {
  type = object({
    endpoint = string
    # the nodes' key, which needs s3:PutObject and s3:ListBucket only: pruning old snapshots falls to the bucket's
    # lifecycle
    access_key    = string
    access_secret = string
    bucket        = string
    region        = optional(string)
    # snapshots RKE2 keeps there, 0 for none pruned: a key without s3:DeleteObject leaves it to the bucket's lifecycle
    retention = number
    # only in the restore_cmd output, s3:GetObject and s3:ListBucket
    restore_access_key    = string
    restore_access_secret = string
  })
  default     = null
  description = "null: none, unless etcd_snapshots_in_object_store makes one."
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

variable "agent_daemonset_tolerations" {
  type = list(object({
    key               = optional(string)
    operator          = optional(string)
    value             = optional(string)
    effect            = optional(string)
    tolerationSeconds = optional(number)
  }))
  default     = null
  description = "Tolerations for node DaemonSets that must run on every agent (Cinder CSI nodePlugin)."
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

variable "object_store_region" {
  type    = string
  default = null
}

variable "identity_endpoint" {
  type = string
}

variable "ff_write_kubeconfig" {
  type    = bool
  default = true
}

variable "ff_lb_subnets_compat" {
  type        = bool
  default     = false
  description = "Enable backward compatibility for existing Load Balancers in the legacy LB subnet"
}

variable "agent_removal_timeout" {
  type        = string
  default     = null
  description = "How long a destroyed agent waits for SSH to drain it and delete its Node; null keeps the Node."
}

variable "etcd_snapshots_in_object_store" {
  type        = bool
  default     = true
  description = "etcd snapshots in a container of the project's object store, at object_store_endpoint; false uses s3_backup."
  validation {
    condition     = !var.etcd_snapshots_in_object_store || (var.object_store_endpoint != "" && var.s3_backup == null)
    error_message = "etcd_snapshots_in_object_store needs object_store_endpoint, and replaces s3_backup: set one of them."
  }
}

variable "ff_wait_ready" {
  type    = bool
  default = true
}

variable "storage_classes" {
  type = list(object({
    name           = string
    reclaim_policy = string
    default        = optional(bool, false)
    # parameters of cinder.csi.openstack.org, e.g. type for a volume type. availability is nova unless
    # set: availability = "" takes the zone of the pod's node, which a region with several zones needs
    parameters = optional(map(string), {})
  }))
  default = [
    { name = "csi-cinder-retain", reclaim_policy = "Retain", default = true },
    { name = "csi-cinder-delete", reclaim_policy = "Delete" },
  ]
  description = "Cinder StorageClasses, each deployed as the manifest <name>.yaml."
  validation {
    condition     = alltrue([for c in var.storage_classes : contains(["Retain", "Delete"], c.reclaim_policy)])
    error_message = "reclaim_policy must be Retain or Delete."
  }
  validation {
    condition     = length(toset(var.storage_classes[*].name)) == length(var.storage_classes)
    error_message = "Storage class names must be unique."
  }
  validation {
    condition     = length([for c in var.storage_classes : c if c.default]) <= 1
    error_message = "At most one storage class can be the default."
  }
}

variable "kube_proxy" {
  type        = bool
  default     = false
  description = "kube-proxy instead of Cilium's kube-proxy replacement."
}

variable "security_groups" {
  type        = bool
  default     = true
  description = "Security groups and port security on the nodes' ports. false for clouds that refuse security groups: UFW alone filters traffic to the nodes."
}

variable "kubelet_config" {
  type        = string
  default     = null
  description = "KubeletConfiguration installed into kubelet.conf.d on every node; null turns graceful node shutdown on."
}

variable "ff_gateway_api_crd" {
  type        = bool
  default     = false
  description = "Let rke2 (v1.37+) install the Gateway API CRDs with its rke2-gateway-api-crd chart. Keep false when the gateway implementation ships its own CRDs."
}

variable "cilium_values" {
  type        = any
  default     = {}
  description = "Top-level keys of the rke2-cilium values the module leaves to the chart, e.g. encryption or hubble."
  validation {
    # a repeated key would replace the module's whole block, not merge into it
    condition     = length(setintersection(keys(var.cilium_values), keys(local.cilium_values))) == 0
    error_message = "cilium_values repeats keys the module sets: ${join(", ", setintersection(keys(var.cilium_values), keys(local.cilium_values)))}."
  }
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
