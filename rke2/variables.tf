
variable "name" {
  type = string
}

variable "ssh_public_key_file" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "public_net_name" {
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

variable "server" {
  type = object({
    nodes_count        = number
    affinity           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    system_user        = string
    boot_volume_size   = number
    rke2_version       = string
    rke2_config_file   = optional(string)
    rke2_volume_size   = number
  })
}

variable "agents" {
  type = list(object({
    name               = string
    nodes_count        = number
    affinity           = optional(string)
    availability_zones = optional(list(string))
    flavor_name        = string
    image_name         = string
    system_user        = string
    boot_volume_size   = number
    rke2_version       = string
    rke2_config_file   = optional(string)
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

variable "manifests_folder" {
  type    = string
  default = ""
}

variable "manifests" {
  type    = map(string)
  default = {}
}

variable "ff_autoremove_agent" {
  type    = bool
  default = true
}
