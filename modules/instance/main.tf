data "openstack_images_image_v2" "image" {
  name        = var.image_name
  most_recent = true
}

resource "openstack_compute_servergroup_v2" "servergroup" {
  name     = "${var.name}-servergroup"
  policies = [var.affinity]
}

resource "openstack_blockstorage_volume_v2" "volume" {
  count = var.nodes_count
  name  = "${openstack_compute_instance_v2.instance[count.index].name}-rke2"
  size  = var.rke2_volume_size
}

resource "openstack_compute_volume_attach_v2" "attach" {
  count       = var.nodes_count
  instance_id = openstack_compute_instance_v2.instance[count.index].id
  volume_id   = openstack_blockstorage_volume_v2.volume[count.index].id
}

resource "openstack_networking_port_v2" "port" {
  count = var.nodes_count

  network_id         = var.network_id
  security_group_ids = var.secgroup_id != null ? [var.secgroup_id] : null
  no_security_groups = var.secgroup_id == null
  admin_state_up     = true

  fixed_ip {
    subnet_id = var.subnet_id
  }

  dynamic "allowed_address_pairs" {
    for_each = var.is_server ? [var.bootstrap_ip] : []
    content {
      ip_address = allowed_address_pairs.value
    }
  }
}

data "openstack_networking_subnet_v2" "subnet" {
  subnet_id = var.subnet_id
}

resource "openstack_compute_instance_v2" "instance" {
  count                   = var.nodes_count
  name                    = var.nodes_count == 1 ? var.name : "${var.name}-${count.index + 1}"
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
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = true
  }

  # yamlencode(yamldecode to debug yaml
  user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yml.tpl", {
    rke2_token   = var.rke2_token
    rke2_version = var.rke2_version
    rke2_conf    = var.rke2_config != null ? var.rke2_config : ""
    is_server    = var.is_server
    bootstrap_ip = var.bootstrap_ip
    is_bootstrap = var.is_bootstrap
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
    failover_cidr    = data.openstack_networking_subnet_v2.subnet.cidr
    vrrp_apiserver   = var.ff_vrrp_apiserver
  }))
}

