terraform {
  required_version = ">= 1.6"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 3"
    }
  }
}
