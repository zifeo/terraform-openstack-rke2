terraform {
  required_version = ">= 1.3.2"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">= 3.4.3"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.1"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.48.0"
    }
  }
}
