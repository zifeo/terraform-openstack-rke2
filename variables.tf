
variable "name" {
  type = string
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "floating_ip_net" {
  type = string
}

variable "external_net_name" {
  type = string
}

variable "rules_ext" {
  type = list(object({
    port     = number
    protocol = string
    source   = string
  }))
}

variable "bootstrap_server" {
  type    = string
  default = "192.168.42.3"
}

variable "subnet_cidr" {
  type    = string
  default = "192.168.42.0/24"
}

variable "dns_nameservers" {
  type = list(string)
  # Cloudflare
  default = ["1.1.1.1", "1.0.0.1"]
}

variable "servers" {
  type = list(object({
    name               = string
    nodes_count        = number
    affinity           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    image_uuid         = optional(string)
    system_user        = string
    boot_volume_size   = number
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
  }))
}

variable "agents" {
  type = list(object({
    name               = string
    nodes_count        = number
    affinity           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    image_uuid         = optional(string)
    system_user        = string
    boot_volume_size   = number
    rke2_version       = string
    rke2_config        = optional(string)
    rke2_volume_size   = number
  }))
}

variable "s3" {
  type = object({
    endpoint      = string
    access_key    = string
    access_secret = string
    bucket        = string
  })
  default = {
    access_key    = ""
    access_secret = ""
    bucket        = ""
    endpoint      = ""
  }
}

variable "cinder" {
  type = object({
    enabled       = bool
    manifest_file = string
  })
  default = {
    enabled       = true
    manifest_file = "./templates/cinder.yml.tpl"
  }
}

variable "manifests_folder" {
  type    = string
  default = ""
}

variable "manifests" {
  type    = map(string)
  default = {}
}

variable "identity_url" {
  type    = string
  default = ""
}


variable "ff_write_kubeconfig" {
  type    = bool
  default = true
}

variable "ff_autoremove_agent" {
  type    = bool
  default = true
}

