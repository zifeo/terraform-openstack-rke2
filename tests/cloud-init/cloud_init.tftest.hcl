variables {
  rke2_version = "v1.37.1+rke2r1"
}

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

run "agent_prebuilt" {
  command = apply

  variables {
    is_server      = false
    gpu_enabled    = false
    image_prebuilt = true
  }

  assert {
    condition     = output.starts_with_cloud_config && !output.package_upgrade && output.package_reboot_if_required == null && length(output.packages) == 0
    error_message = "A prebuilt image already ran the package part: its user_data must not update, upgrade, reboot or install packages."
  }
}

run "agent_with_gpu_prebuilt" {
  command = apply

  variables {
    is_server      = false
    gpu_enabled    = true
    image_prebuilt = true
  }

  assert {
    condition     = !output.package_upgrade && output.packages == ["nvidia-driver-580", "nvidia-container-toolkit"]
    error_message = "A prebuilt GPU image still installs the driver and toolkit at launch, and nothing else."
  }
}
