terraform {
  required_version = ">= 0.14.0"

  required_providers {
    null = {
      source = "hashicorp/null"
    }
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
