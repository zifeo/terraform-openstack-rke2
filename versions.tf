terraform {
  required_version = ">= 1.3.2"

  required_providers {
    random = {
      source = "hashicorp/random"
    }
    null = {
      source = "hashicorp/null"
    }
    openstack = {
      source = "terraform-provider-openstack/openstack"
    }
  }
}
