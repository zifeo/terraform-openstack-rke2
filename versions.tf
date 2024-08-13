terraform {
  required_version = ">= 1.3.3"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.2"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1.0"
    }
  }
}
