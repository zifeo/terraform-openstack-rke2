terraform {
  required_version = ">= 1.3.3"

  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
