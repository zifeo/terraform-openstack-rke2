terraform {
  required_version = ">= 1.9"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = ">= 3"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = ">= 3"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4"
    }
  }
}
