terraform {
  required_providers {
    local = {
      source = "hashicorp/local"
    }
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

  experiments = [module_variable_optional_attrs]
}

