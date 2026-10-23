terraform {
  required_version = ">= 1.6"

  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4"
    }
  }
}

variable "is_server" {
  type = bool
}

variable "gpu_enabled" {
  type = bool
}

variable "gpu_driver_preinstalled" {
  type    = bool
  default = false
}

variable "bootstrap" {
  type    = bool
  default = false
}

# the cluster's servers: the operators' replicas follow them, as in ../../main.tf
variable "servers" {
  type    = number
  default = 3
}

# the untainted agent nodes, which main.tf counts for CoreDNS and metrics-server
variable "untainted_agents" {
  type    = number
  default = 2
}

# the bootstrap server is the first; a first server replaced once bootstrap is false joins
variable "is_first" {
  type    = bool
  default = false
}

variable "rke2_version" {
  type = string
}

variable "image_prebuilt" {
  type    = bool
  default = false
}

variable "cilium_values" {
  type    = any
  default = {}
}

# what ../../firewall takes, the e2e's single network as both subnets, and the rules a test adds on every node (its own
# SSH path)
variable "firewall" {
  type = object({
    subnet_cidr    = string
    rules_ssh_cidr = list(string)
    rules_k8s_cidr = list(string)
    extra = list(object({
      protocol = string
      port     = string
      from     = string
    }))
  })
  default = {
    subnet_cidr    = "10.0.0.0/24"
    rules_ssh_cidr = ["0.0.0.0/0"]
    rules_k8s_cidr = ["192.0.2.0/24"]
    extra          = []
  }
}

variable "ssh_authorized_keys" {
  type    = list(string)
  default = []
}

variable "ff_gateway_api_crd" {
  type    = bool
  default = false
}

variable "node_ip" {
  type    = string
  default = "10.0.0.11"
}

variable "node_labels" {
  type    = map(string)
  default = {}
}

# rendered "key=value:Effect", like node/main.tf
variable "node_taints" {
  type    = list(string)
  default = []
}

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

# the module's registries input, which the e2e points at its caches
variable "registries" {
  type    = any
  default = null
}

variable "rke2_config" {
  type    = string
  default = ""
}

# the module's manifests input, merged last as main.tf does
variable "manifests" {
  type    = map(string)
  default = {}
}

variable "runtime_classes" {
  type = map(object({
    handler      = string
    runtime_type = string
    options      = map(string)
  }))
  default = {}
}

variable "daemonset_tolerations" {
  type = list(map(string))
  default = [
    { key = "dedicated", operator = "Equal", value = "fixture", effect = "NoSchedule" },
    { operator = "Exists", effect = "NoExecute" },
  ]
}

# the node's SSH host key, which tofu makes and pins
resource "tls_private_key" "host" {
  algorithm = "ED25519"
}

# what tofu pushes over SSH before rke2 starts, as node/main.tf renders it: distinct values, so that a test sees
# whether any of them reaches user_data
module "secrets" {
  source = "../../node/secrets"

  token       = var.is_server ? "fixture-server-token" : "fixture-agent-token"
  agent_token = var.is_server ? "fixture-agent-token" : null
  s3          = var.is_server && var.s3 != null ? { access_key = var.s3.access_key, access_secret = var.s3.access_secret } : null
  registries  = var.registries
  cinder_credentials = var.is_server ? templatefile("${path.module}/../../manifests/csi-cinder-credentials.conf.tpl", {
    auth_url   = "https://identity.fixture.invalid"
    region     = "fixture-region"
    project_id = "fixture-project"
    app_id     = "fixture-app-id"
    app_secret = "fixture-app-secret" # checkov:skip=CKV_SECRET_6:the tests look for this placeholder
    app_name   = "fixture-app"
  }) : null
}

locals {
  # mirrors the manifests map of ../../main.tf with fixture values; templatefile fails on any variable missing here
  credentials = {
    auth_url   = "https://identity.fixture.invalid"
    region     = "fixture-region"
    project_id = "fixture-project"
    app_id     = "fixture-app-id"
    app_secret = "fixture-app-secret" # checkov:skip=CKV_SECRET_6:the tests look for this placeholder
    app_name   = "fixture-app"
  }
  manifests = merge(
    {
      "cinder-csi.yaml" = templatefile("${path.module}/../../manifests/csi-cinder.yaml.tpl", {
        operator_replica        = var.servers > 1 ? 2 : 1
        node_plugin_tolerations = var.daemonset_tolerations
      })
      "cloud-controller-openstack.yaml" = templatefile("${path.module}/../../manifests/cloud-controller-openstack.yaml.tpl", {
        cluster_name = "fixture"
      })
      "patches/rke2-cilium.yaml" = yamlencode(merge(yamldecode(templatefile("${path.module}/../../patches/rke2-cilium.yaml.tpl", {
        operator_replica = var.servers > 1 ? 2 : 1
        cluster_name     = "fixture"
        cluster_id       = 1
        kube_proxy       = false
        nodeport_cidr    = var.firewall.subnet_cidr
      })), var.cilium_values))
      "patches/rke2-coredns.yaml" = templatefile("${path.module}/../../patches/rke2-coredns.yaml.tpl", {
        agent_replica = min(2, var.untainted_agents)
      })
      "patches/rke2-metrics-server.yaml" = templatefile("${path.module}/../../patches/rke2-metrics-server.yaml.tpl", {
        agent_replica = min(2, var.untainted_agents)
      })
      "ceph-perf1-retain.yaml" = templatefile("${path.module}/../../manifests/csi-cinder-sc.yaml.tpl", {
        name          = "ceph-perf1-retain"
        reclaimPolicy = "Retain"
        is_default    = true
        parameters    = { type = "CEPH_1_perf1" }
      })
      "csi-cinder-delete.yaml" = templatefile("${path.module}/../../manifests/csi-cinder-sc.yaml.tpl", {
        name          = "csi-cinder-delete"
        reclaimPolicy = "Delete"
        is_default    = false
        parameters    = {}
      })
      "zoned.yaml" = templatefile("${path.module}/../../manifests/csi-cinder-sc.yaml.tpl", {
        name          = "zoned"
        reclaimPolicy = "Delete"
        is_default    = false
        parameters    = { availability = "", type = "high-speed" }
      })
    },
    { for f in fileset("${path.module}/../../manifests", "*.{yml,yaml}") : f => file("${path.module}/../../manifests/${f}") },
    {
      for name, rc in var.runtime_classes : "runtimeclass-${name}.yaml" => templatefile("${path.module}/../../manifests/runtimeclass.yaml.tpl", {
        name          = name
        handler       = rc.handler
        node_selector = { "example.com/pool" = "sandboxed" }
        tolerations   = [{ key = "example.com/pool", operator = "Equal", value = "sandboxed", effect = "NoSchedule" }]
      })
    },
    var.manifests,
  )

  # what the module applies through the API, as main.tf renders it
  cluster_secrets = templatefile("${path.module}/../../manifests/cloud-config-secrets.yaml.tpl", merge(local.credentials, {
    network_id          = "fixture-network"
    subnet_id           = "fixture-subnet"
    floating_network_id = "fixture-floating"
    lb_provider         = "amphora"
    manage_sg           = true
  }))

  rendered = templatefile("${path.module}/../../node/cloud-init.yaml.tpl", {
    image_prebuilt     = var.image_prebuilt
    node_config_script = file("${path.module}/../../node/rke2-node-config.py")
    kubelet_config     = null
    host_key = {
      private = tls_private_key.host.private_key_openssh
      public  = trimspace(tls_private_key.host.public_key_openssh)
    }
    secrets_sha256          = nonsensitive(sha256(join("", [module.secrets.token, module.secrets.config, module.secrets.registries, module.secrets.cinder != null ? module.secrets.cinder : ""])))
    cinder_node             = module.secrets.cinder_node
    rke2_version            = var.rke2_version
    rke2_conf               = var.rke2_config
    rke2_device             = "/dev/vdb"
    is_server               = var.is_server
    is_first                = var.is_first || var.bootstrap
    internal_vip            = "10.0.0.10"
    node_ip                 = var.node_ip
    cluster_cidr            = "10.42.0.0/16"
    service_cidr            = "10.43.0.0/16"
    san                     = ["10.0.0.10"]
    manifests_files         = var.is_server ? { for k, v in local.manifests : k => base64gzip(v) } : {}
    s3                      = var.s3
    backup_schedule         = null
    backup_retention        = null
    control_plane_requests  = ""
    control_plane_limits    = ""
    system_user             = "ubuntu"
    customize_chart_script  = base64gzip(file("${path.module}/../../node/customize-chart.sh"))
    customize_charts_script = base64gzip(file("${path.module}/../../node/customize-charts.sh"))
    kube_proxy              = false
    nodeport_cidr           = var.firewall.subnet_cidr
    ff_gateway_api_crd      = var.ff_gateway_api_crd
    node_taints             = var.node_taints
    node_labels             = var.node_labels
    runtime_classes         = values(var.runtime_classes)
    gpu = {
      enabled = var.gpu_enabled
      driver = {
        package      = "nvidia-driver-580"
        version      = null
        preinstalled = var.gpu_driver_preinstalled
      }
      toolkit_package = "nvidia-container-toolkit"
      toolkit_version = null
    }
  })

  # yamldecode rejects unknown tags such as !false, which is how cloud-init fails closed.
  parsed = yamldecode(local.rendered)
}

# the host key makes all of user_data sensitive, not these
output "package_reboot_if_required" {
  value = nonsensitive(try(local.parsed.package_reboot_if_required, null))
}

output "package_upgrade" {
  value = nonsensitive(try(local.parsed.package_upgrade, false))
}

output "packages" {
  value = nonsensitive(try(local.parsed.packages, []))
}

output "starts_with_cloud_config" {
  value = nonsensitive(startswith(local.rendered, "#cloud-config"))
}

output "rendered" {
  value     = local.rendered
  sensitive = true
}

# what the e2e pushes, standing in for tofu: config.yaml.d/50-secrets.yaml and registries.yaml before rke2 starts, the
# cluster's Secrets once the API answers
output "secrets" {
  value = {
    config     = module.secrets.config
    registries = module.secrets.registries
    cinder     = module.secrets.cinder
    token      = module.secrets.token
    token_user = var.is_server ? "server" : "node"
    bootstraps = var.bootstrap
    join       = var.is_first && !var.bootstrap ? "server: \"https://10.0.0.10:9345\"\n" : ""
  }
  sensitive = true
}

output "cluster_secrets" {
  value = local.cluster_secrets
}

output "host_key" {
  value = trimspace(tls_private_key.host.public_key_openssh)
}

output "manifests" {
  value = local.manifests
}

output "daemonset_tolerations" {
  value = var.daemonset_tolerations
}

module "firewall" {
  source = "../../firewall"

  subnet_servers_cidr = var.firewall.subnet_cidr
  subnet_agents_cidr  = var.firewall.subnet_cidr
  subnet_lb_cidr      = null
  cluster_cidr        = "10.42.0.0/16"
  rules_ssh_cidr      = var.firewall.rules_ssh_cidr
  rules_k8s_cidr      = var.firewall.rules_k8s_cidr
  rules               = {}
}

# what node/main.tf gives the instance's metadata, which the e2e serves to its VMs
module "metadata" {
  source = "../../node/metadata"

  rke2_version        = var.rke2_version
  role                = var.is_server ? "server" : "agent"
  bootstrap           = var.bootstrap
  ssh_authorized_keys = var.ssh_authorized_keys
  firewall            = concat(module.firewall.ufw[var.is_server ? "server" : "agent"], var.firewall.extra)
}

output "metadata" {
  value = module.metadata.metadata
}

# what tofu pushes as /etc/rancher/rke2-node-config.json
output "node_config" {
  value = jsondecode(module.metadata.config)
}
