run "agent_without_gpu" {
  command = apply

  variables {
    is_server   = false
    gpu_enabled = false
  }

  assert {
    condition     = output.starts_with_cloud_config && output.package_reboot_if_required == true
    error_message = "Non-GPU cloud-init must parse as YAML and set package_reboot_if_required to boolean true. A leading ! renders a YAML tag such as !false, which cloud-init refuses."
  }
}

run "agent_with_gpu" {
  command = apply

  variables {
    is_server               = false
    gpu_enabled             = true
    gpu_driver_preinstalled = false
  }

  assert {
    condition     = output.starts_with_cloud_config && output.package_reboot_if_required == false
    error_message = "GPU cloud-init must parse as YAML and set package_reboot_if_required to boolean false so cloud-init does not reboot over the driver install."
  }
}

run "agent_with_preinstalled_gpu_driver" {
  command = apply

  variables {
    is_server               = false
    gpu_enabled             = true
    gpu_driver_preinstalled = true
  }

  assert {
    condition     = output.starts_with_cloud_config && output.package_reboot_if_required == false
    error_message = "GPU cloud-init with a preinstalled driver must still parse, with package_reboot_if_required set to boolean false."
  }
}

run "server_bootstrap" {
  command = apply

  variables {
    is_server   = true
    gpu_enabled = false
    bootstrap   = true
  }

  assert {
    condition     = output.starts_with_cloud_config && output.package_reboot_if_required == true
    error_message = "Bootstrap server cloud-init must parse as YAML and set package_reboot_if_required to boolean true."
  }
}

run "server_join" {
  command = apply

  variables {
    is_server   = true
    gpu_enabled = false
    bootstrap   = false
  }

  assert {
    condition     = output.starts_with_cloud_config && output.package_reboot_if_required == true
    error_message = "Joining server cloud-init must parse as YAML and set package_reboot_if_required to boolean true."
  }
}
