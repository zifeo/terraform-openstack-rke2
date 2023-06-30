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

variable "affinity" {
  type = string
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "san" {
  type    = list(string)
  default = []
}

variable "secgroup_id" {
  type = string
}

variable "bootstrap_ip" {
  type    = string
  default = ""
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
  type = bool
}

variable "ssh_authorized_keys" {
  type = list(string)
}
