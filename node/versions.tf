terraform {
  required_version = ">= 1.3.3"

  required_providers {
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
