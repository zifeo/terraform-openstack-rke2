locals {
  s3 = var.ff_native_backup != "" && var.object_store_endpoint != "" ? {
    endpoint      = var.object_store_endpoint
    access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots[0].name
  } : var.s3_backup

  proxy_ip = var.floating_pool != "" ? openstack_networking_floatingip_v2.floating_ip[0].address : module.servers[0].external_ips[0]
}

module "servers" {
  source = "./modules/instance"

  for_each = {
    for server in var.servers :
    index(var.servers, server) => server
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = true
  is_bootstrap = each.key == "0"

  nodes_count      = 1
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version     = each.value.rke2_version
  rke2_config      = each.value.rke2_config
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = each.value.rke2_volume_size

  s3 = local.s3

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.servers.id
  subnet_id        = openstack_networking_subnet_v2.servers.id
  secgroup_id      = openstack_networking_secgroup_v2.server.id
  bootstrap_server = var.bootstrap_server
  failover_ips = var.floating_pool == "" ? [] : concat(
    [openstack_networking_port_v2.port[each.key].all_fixed_ips[0]],
    length(var.servers) > 1 ? [openstack_networking_port_v2.port[(each.key + 1) % length(var.servers)].all_fixed_ips[0]] : []
  )
  san = openstack_networking_floatingip_v2.floating_ip[*].address

  manifests_folder = var.manifests_folder
  manifests = merge(
    {
      "cinder-csi.yml" : templatefile("${path.module}/templates/csi-cinder.yml.tpl", {
        auth_url   = var.identity_endpoint
        region     = openstack_identity_application_credential_v3.rke2.region
        project_id = openstack_identity_application_credential_v3.rke2.project_id
        app_id     = openstack_identity_application_credential_v3.rke2.id
        app_secret = openstack_identity_application_credential_v3.rke2.secret
        app_name   = openstack_identity_application_credential_v3.rke2.name
      }),
      "csi-cinder-snapclass.yml" : file("${path.module}/manifests/csi-cinder-snapclass.yml"),
      "velero.yml" : templatefile("${path.module}/templates/velero.yml.tpl", {
        auth_url   = var.identity_endpoint
        region     = openstack_identity_application_credential_v3.rke2.region
        project_id = openstack_identity_application_credential_v3.rke2.project_id
        app_id     = openstack_identity_application_credential_v3.rke2.id
        app_secret = openstack_identity_application_credential_v3.rke2.secret
        app_name   = openstack_identity_application_credential_v3.rke2.name
      }),
      "csi-cinder-delete.yml" : file("${path.module}/manifests/csi-cinder-delete.yml"),
      "csi-cinder-retain.yml" : file("${path.module}/manifests/csi-cinder-retain.yml"),
      "cloud-controller-openstack.yml" : templatefile("${path.module}/templates/cloud-controller-openstack.yml.tpl", {
        auth_url            = var.identity_endpoint
        region              = openstack_identity_application_credential_v3.rke2.region
        project_id          = openstack_identity_application_credential_v3.rke2.project_id
        app_id              = openstack_identity_application_credential_v3.rke2.id
        app_secret          = openstack_identity_application_credential_v3.rke2.secret
        app_name            = openstack_identity_application_credential_v3.rke2.name
        subnet_id           = openstack_networking_subnet_v2.agents.id
        floating_network_id = var.floating_pool != "" ? data.openstack_networking_network_v2.floating_net[0].id : null
        cluster_name        = var.name
      }),
    },
    var.manifests,
  )

  ff_autoremove_agent = false
  ff_vrrp_apiserver   = var.ff_vrrp_apiserver
}

data "openstack_networking_network_v2" "net-ext" {
  name = "ext-net1"
}

data "openstack_networking_subnet_ids_v2" "subnet-ext" {
  network_id = data.openstack_networking_network_v2.net-ext.id
  ip_version = "4"
}

module "agents" {
  source = "./modules/instance"

  for_each = {
    for agent in var.agents :
    index(var.agents, agent) => agent
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = false
  is_bootstrap = false

  nodes_count      = each.value.nodes_count
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size

  availability_zones = coalesce(each.value.availability_zones, [])
  affinity           = coalesce(each.value.affinity, "soft-anti-affinity")

  rke2_version     = each.value.rke2_version
  rke2_config      = each.value.rke2_config
  rke2_token       = random_string.rke2_token.result
  rke2_volume_size = each.value.rke2_volume_size

  system_user  = each.value.system_user
  keypair_name = openstack_compute_keypair_v2.key.name

  network_id       = openstack_networking_network_v2.agents.id
  subnet_id        = openstack_networking_subnet_v2.agents.id
  secgroup_id      = openstack_networking_secgroup_v2.agent.id
  bootstrap_server = var.bootstrap_server
  bastion_host     = local.proxy_ip

  ff_autoremove_agent = var.ff_autoremove_agent
  ff_vrrp_apiserver   = false
}
