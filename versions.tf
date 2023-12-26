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
      source = "terraform-provider-openstack/openstack"
      # 1.5x.x is affected by https://github.com/terraform-provider-openstack/terraform-provider-openstack/issues/1601
      version = "~> 1.53.0"
    }
  }
}
