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

locals {
  rendered = templatefile("${path.module}/../../node/cloud-init.yaml.tpl", {
    rke2_token   = "token"
    rke2_version = "v1.35.6+rke2r1"
    rke2_conf    = ""
    rke2_device  = "/dev/vdb"
    is_server    = var.is_server
    bootstrap    = var.bootstrap
    internal_vip = "10.0.0.10"
    node_ip      = "10.0.0.11"
    cluster_cidr = "10.42.0.0/16"
    service_cidr = "10.43.0.0/16"
    cni          = "cilium"
    san          = ["10.0.0.10"]
    manifests_files = {
      "example.yaml" = base64gzip("kind: ConfigMap\n")
    }
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
