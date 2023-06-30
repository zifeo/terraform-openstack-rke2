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
      source = "terraform-provider-openstack/openstack"
      # 1.5x.x misses a bool state value for openstack_objectstorage_container_v1
      version = "~> 1.49.0"
    }
  }
}
