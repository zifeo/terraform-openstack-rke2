terraform {
  required_version = ">= 1.6"
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

variable "node_ip" {
  type    = string
  default = "10.0.0.11"
}

variable "daemonset_tolerations" {
  type = list(map(string))
  default = [
    { key = "dedicated", operator = "Equal", value = "fixture", effect = "NoSchedule" },
    { operator = "Exists", effect = "NoExecute" },
  ]
}

locals {
  # mirrors the manifests map of ../../main.tf with fixture values; templatefile fails on any variable missing here
  credentials = {
    auth_url   = "https://identity.fixture.invalid"
    region     = "fixture-region"
    project_id = "fixture-project"
    app_id     = "fixture-app-id"
    app_secret = "fixture"
    app_name   = "fixture-app"
  }
  manifests = merge(
    {
      "cinder-csi.yaml" = templatefile("${path.module}/../../manifests/csi-cinder.yaml.tpl", merge(local.credentials, {
        operator_replica        = 3
        node_plugin_tolerations = var.daemonset_tolerations
      }))
      "velero.yaml" = templatefile("${path.module}/../../manifests/velero.yaml.tpl", merge(local.credentials, {
        bucket_restic          = "fixture-restic"
        bucket_velero          = "fixture-velero"
        node_agent_tolerations = var.daemonset_tolerations
      }))
      "cloud-controller-openstack.yaml" = templatefile("${path.module}/../../manifests/cloud-controller-openstack.yaml.tpl", merge(local.credentials, {
        network_id          = "fixture-network"
        subnet_id           = "fixture-subnet"
        floating_network_id = "fixture-floating"
        lb_provider         = "amphora"
        cluster_name        = "fixture"
      }))
      "patches/rke2-cilium.yaml" = templatefile("${path.module}/../../patches/rke2-cilium.yaml.tpl", {
        operator_replica       = 3
        cluster_name           = "fixture"
        cluster_id             = 1
        ff_with_kubeproxy      = false
        enable_encryption      = false
        encryption_type        = "wireguard"
        enable_node_encryption = false
      })
      "patches/rke2-coredns.yaml" = templatefile("${path.module}/../../patches/rke2-coredns.yaml.tpl", {
        operator_replica = 3
      })
      "sc-ceph-perf1-retain.yaml" = templatefile("${path.module}/../../manifests/csi-cinder-sc.yaml.tpl", {
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
    },
    { for f in fileset("${path.module}/../../manifests", "*.{yml,yaml}") : f => file("${path.module}/../../manifests/${f}") },
  )

  rendered = templatefile("${path.module}/../../node/cloud-init.yaml.tpl", {
    rke2_token      = "token"
    rke2_version    = "v1.35.6+rke2r1"
    rke2_conf       = ""
    rke2_device     = "/dev/vdb"
    is_server       = var.is_server
    bootstrap       = var.bootstrap
    internal_vip    = "10.0.0.10"
    node_ip         = var.node_ip
    cluster_cidr    = "10.42.0.0/16"
    service_cidr    = "10.43.0.0/16"
    cni             = "cilium"
    san             = ["10.0.0.10"]
    manifests_files = var.is_server ? { for k, v in local.manifests : k => base64gzip(v) } : {}
    s3 = {
      endpoint      = ""
      access_key    = ""
      access_secret = ""
      bucket        = ""
      region        = null
    }
    backup_schedule         = null
    backup_retention        = null
    control_plane_requests  = ""
    control_plane_limits    = ""
    system_user             = "ubuntu"
    customize_chart_script  = base64gzip(file("${path.module}/../../node/customize-chart.sh"))
    customize_charts_script = base64gzip(file("${path.module}/../../node/customize-charts.sh"))
    authorized_keys         = []
    ff_with_kubeproxy       = false
    node_taints             = []
    node_labels             = {}
    registries              = null
    gpu = {
      enabled = var.gpu_enabled
      driver = {
        package      = "nvidia-driver-550"
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

output "package_reboot_if_required" {
  value = local.parsed.package_reboot_if_required
}

output "starts_with_cloud_config" {
  value = startswith(local.rendered, "#cloud-config")
}

output "rendered" {
  value = local.rendered
}

output "manifests" {
  value = local.manifests
}

output "daemonset_tolerations" {
  value = var.daemonset_tolerations
}
