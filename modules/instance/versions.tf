terraform {
  required_version = ">= 0.14.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 1.44.0"
    }
  }
}
