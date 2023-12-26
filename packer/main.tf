resource "openstack_networking_secgroup_v2" "packer_secgroup" {
  name = "packer-sg"
}

resource "openstack_networking_secgroup_rule_v2" "packer_ssh" {
  direction      = "ingress"
  ethertype      = "IPv4"
  protocol       = "tcp"
  port_range_min = 22
  port_range_max = 22
  # checkov:skip=CKV_OPENSTACK_2
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.packer_secgroup.id
}

data "openstack_networking_network_v2" "net" {
  name = "ext-net1"
}


variable "project" {
  type = string
}

variable "username" {
  type = string
}

variable "password" {
  type = string
}

resource "null_resource" "packer_build" {
  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    environment = {
      PKR_VAR_project             = var.project
      PKR_VAR_username            = var.username
      PKR_VAR_password            = var.password
      PKR_VAR_network_id          = data.openstack_networking_network_v2.net.id
      PKR_VAR_security_group_name = openstack_networking_secgroup_v2.packer_secgroup.name
    }
    command = <<-EOT
      packer build rke2.pkr.hcl
    EOT
  }
}
