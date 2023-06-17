terraform {
  required_version = ">= 1.3.3"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.1"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.51.1"
    }
  }
}
