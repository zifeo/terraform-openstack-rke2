data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

resource "openstack_compute_servergroup_v2" "servergroup" {
  name     = "${var.name}-servergroup"
  policies = [var.affinity]
}

resource "openstack_blockstorage_volume_v3" "volume" {
  count                = var.is_persisted ? var.nodes_count : 0
  name                 = "${var.name}-${count.index + 1}-rke2"
  size                 = var.rke2_volume_size
  volume_type          = var.rke2_volume_type
  enable_online_resize = true
}

resource "openstack_networking_port_v2" "port" {
  count = var.nodes_count

  network_id         = var.network_id
  security_group_ids = [var.secgroup_id]
  admin_state_up     = true

  fixed_ip {
    subnet_id = var.subnet_id
  }
}

resource "openstack_compute_instance_v2" "instance" {
  count                   = var.nodes_count
  name                    = "${var.name}-${count.index + 1}"
  availability_zone_hints = length(var.availability_zones) > 0 ? var.availability_zones[count.index % length(var.availability_zones)] : null

  flavor_name  = var.flavor_name
  key_pair     = var.keypair_name
  config_drive = true

  network {
    port = openstack_networking_port_v2.port[count.index].id
  }

  scheduler_hints {
    group = openstack_compute_servergroup_v2.servergroup.id
  }

  metadata = {
    rke2_version = var.rke2_version
    rke2_role    = var.is_server ? "server" : "agent"
  }

  block_device {
    uuid                  = var.image_uuid != null ? var.image_uuid : data.openstack_images_image_v2.image.id
    source_type           = "image"
    volume_size           = var.boot_volume_size
    volume_type           = var.boot_volume_type
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  block_device {
    uuid                  = var.is_persisted ? openstack_blockstorage_volume_v3.volume[count.index].id : null
    source_type           = var.is_persisted ? "volume" : "blank"
    boot_index            = 1
    destination_type      = "volume"
    volume_size           = var.is_persisted ? null : var.rke2_volume_size
    volume_type           = var.is_persisted ? null : var.rke2_volume_type
    delete_on_termination = var.is_persisted ? false : true
    # currently, you cannot enable online resize and delete_on_termination
    # this requires 2 apply per node (1 pass to delete the server, 1 pass to create the server)
    # https://github.com/terraform-provider-openstack/terraform-provider-openstack/issues/1545
    # potential solution: https://github.com/hashicorp/terraform/issues/31707
  }

  # yamlencode(yamldecode to debug yaml
  user_data = base64encode(templatefile("${path.module}/cloud-init.yml.tpl", {
    rke2_token   = var.rke2_token
    rke2_version = var.rke2_version
    rke2_conf    = var.rke2_config != null ? var.rke2_config : ""
    rke2_device  = var.rke2_volume_device
    is_server    = var.is_server
    is_first     = var.is_first && count.index == 0
    bootstrap    = var.bootstrap && var.is_first && count.index == 0
    bootstrap_ip = var.bootstrap_ip
    node_ip      = openstack_networking_port_v2.port[count.index].all_fixed_ips[0]
    san          = var.is_server ? var.san : []
    manifests_files = var.is_server ? merge(
      var.manifests_folder != "" ? {
        for f in fileset(var.manifests_folder, "*.{yml,yaml}") : f => base64gzip(file("${var.manifests_folder}/${f}"))
      } : {},
      { for k, v in var.manifests : k => base64gzip(v) },
    ) : {}
    s3_endpoint      = var.s3.endpoint
    s3_access_key    = var.s3.access_key
    s3_access_secret = var.s3.access_secret
    s3_bucket        = var.s3.bucket
    system_user      = var.system_user
    authorized_keys  = join("\n", var.ssh_authorized_keys)
  }))
}

/*
resource "local_file" "debug" {
  count    = var.nodes_count
  filename = "${path.module}/${var.name}-${count.index + 1}.yml"
  content = 
}
*/
