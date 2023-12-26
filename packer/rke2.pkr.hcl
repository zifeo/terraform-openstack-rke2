
variable "project" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

variable "network_id" {
  type = string
}

variable "security_group_name" {
  type = string
}

source "openstack" "rke2" {
  #source_image_name = "Ubuntu 22.04 LTS Jammy Jellyfish"
  source_image_filter {
    filters {
      name = "Ubuntu 22.04 LTS Jammy Jellyfish"
    }
    most_recent = true
  }
  ssh_username      = "ubuntu"
  flavor            = "a2-ram4-disk0"
  image_name        = "ubuntu-22.04-rke2"
  image_disk_format = "qcow2"
  image_visibility  = "shared"
  image_members = [] # project/tenant id

  identity_endpoint = "https://api.pub1.infomaniak.cloud/identity"
  domain_name       = "default"
  tenant_name       = var.project
  username          = var.username
  password          = var.password
  region            = "dc3-a"

  networks        = [var.network_id]
  security_groups = [var.security_group_name]
  use_blockstorage_volume = true
  image_min_disk = 1
  volume_size = 1
}

source "qemu" "rke2" {
  iso_url     = "./ubuntu-22.04.img"
  iso_checksum = "md5:e6fd605efc9dd5f5a3770f7a4682aefd"
  disk_interface    = "virtio"

  format         = "qcow2"
  headless       = true
  ssh_username      = "ubuntu"
}

build {
  sources = ["source.openstack.rke2"]

  provisioner "ansible" {
    playbook_file = "./playbook.yml"
    # https://github.com/hashicorp/packer-plugin-ansible/issues/110
    extra_arguments = [ "-v", "--scp-extra-args", "'-O'" ]
  }
}
