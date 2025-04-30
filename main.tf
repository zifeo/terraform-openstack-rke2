locals {
  s3 = var.ff_native_backup && var.object_store_endpoint != "" ? {
    endpoint      = var.object_store_endpoint
    access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots[0].name
  } : var.s3_backup

  external_ip      = openstack_networking_floatingip_v2.floating_ip.address
  internal_vip     = var.subnet_servers_vip != null ? var.subnet_servers_vip : cidrhost(var.subnet_servers_cidr, 4)
  operator_replica = length(var.servers) > 1 ? 2 : 1
}

resource "openstack_compute_servergroup_v2" "servers" {
  name     = "${var.name}-servers"
  policies = ["anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "agents" {
  name     = "${var.name}-servers"
  policies = ["soft-anti-affinity"]
}

module "servers" {
  source = "./node"

  for_each = {
    for server in var.servers :
    server.name => server
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = true
  is_first     = var.servers[0].name == each.value.name
  is_persisted = length(var.servers) == 1
  bootstrap    = var.bootstrap

  nodes_count      = 1
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size
  boot_volume_type = each.value.boot_volume_type

  availability_zones = coalesce(each.value.availability_zones, [])
  group_id           = each.value.group_id != null ? each.value.group_id : openstack_compute_servergroup_v2.servers.id

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_string.rke2_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  s3               = local.s3
  backup_schedule  = var.backup_schedule
  backup_retention = var.backup_retention

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id    = openstack_networking_network_v2.net.id
  subnet_id     = openstack_networking_subnet_v2.servers.id
  secgroup_id   = openstack_networking_secgroup_v2.server.id
  internal_vip  = local.internal_vip
  vip_interface = var.vip_interface
  bastion_host  = local.external_ip
  san           = distinct(concat([local.external_ip, local.internal_vip], var.additional_san))

  manifests_folder = var.manifests_folder
  manifests = merge(
    {
      "cinder-csi.yaml" : templatefile("${path.module}/manifests/csi-cinder.yaml.tpl", {
        operator_replica = local.operator_replica
        auth_url         = var.identity_endpoint
        region           = openstack_identity_application_credential_v3.rke2.region
        project_id       = openstack_identity_application_credential_v3.rke2.project_id
        app_id           = openstack_identity_application_credential_v3.rke2.id
        app_secret       = openstack_identity_application_credential_v3.rke2.secret
        app_name         = openstack_identity_application_credential_v3.rke2.name
      }),
      "velero.yaml" : templatefile("${path.module}/manifests/velero.yaml.tpl", {
        auth_url      = var.identity_endpoint
        region        = openstack_identity_application_credential_v3.rke2.region
        app_id        = openstack_identity_application_credential_v3.rke2.id
        app_secret    = openstack_identity_application_credential_v3.rke2.secret
        app_name      = openstack_identity_application_credential_v3.rke2.name
        bucket_restic = openstack_objectstorage_container_v1.restic.name
        bucket_velero = openstack_objectstorage_container_v1.velero.name
      }),
      "cloud-controller-openstack.yaml" : templatefile("${path.module}/manifests/cloud-controller-openstack.yaml.tpl", {
        auth_url            = var.identity_endpoint
        region              = openstack_identity_application_credential_v3.rke2.region
        project_id          = openstack_identity_application_credential_v3.rke2.project_id
        app_id              = openstack_identity_application_credential_v3.rke2.id
        app_secret          = openstack_identity_application_credential_v3.rke2.secret
        app_name            = openstack_identity_application_credential_v3.rke2.name
        network_id          = openstack_networking_network_v2.net.id
        subnet_id           = openstack_networking_subnet_v2.lb.id
        floating_network_id = data.openstack_networking_network_v2.floating_net.id
        lb_provider         = var.lb_provider
        cluster_name        = var.name
      }),
      "patches/rke2-cilium.yaml" : templatefile("${path.module}/patches/rke2-cilium.yaml.tpl", {
        operator_replica = local.operator_replica
        cluster_name     = var.name
        cluster_id       = var.cluster_id
        ff_kubeproxy     = var.ff_kubeproxy
      }),
      "patches/rke2-coredns.yaml" : templatefile("${path.module}/patches/rke2-coredns.yaml.tpl", {
        operator_replica = local.operator_replica
      }),
      "patches/rke2-metrics-server.yaml" : templatefile("${path.module}/patches/rke2-metrics-server.yaml.tpl", {
      }),
      "patches/rke2-snapshot-controller.yaml" : templatefile("${path.module}/patches/rke2-snapshot-controller.yaml.tpl", {
      }),
      "patches/rke2-snapshot-validation-webhook.yaml" : templatefile("${path.module}/patches/rke2-snapshot-validation-webhook.yaml.tpl", {
      }),
    },
    var.ff_infomaniak_sc ? merge([for perf in ["perf1", "perf2", "perf3"] : {
      "sc-ceph-${perf}-delete.yaml" : templatefile("${path.module}/manifests/csi-cinder-sc.yaml.tpl", {
        name          = "ceph-${perf}-delete"
        reclaimPolicy = "Delete"
        is_default    = false
        parameters = {
          type = "CEPH_1_${perf}"
        }
      })
    }]...) : {},
    var.ff_infomaniak_sc ? merge([for perf in ["perf1", "perf2", "perf3"] : {
      "sc-ceph-${perf}-retain.yaml" : templatefile("${path.module}/manifests/csi-cinder-sc.yaml.tpl", {
        name          = "ceph-${perf}-retain"
        reclaimPolicy = "Retain"
        is_default    = perf == "perf1"
        parameters = {
          type = "CEPH_1_${perf}"
        }
      })
      }]...) : {
      "csi-cinder-retain.yaml" : templatefile("${path.module}/manifests/csi-cinder-sc.yaml.tpl", {
        name          = "csi-cinder-retain",
        reclaimPolicy = "Retain"
        is_default    = true
        parameters    = {}
      }),
      "csi-cinder-delete.yaml" : templatefile("${path.module}/manifests/csi-cinder-sc.yaml.tpl", {
        name          = "csi-cinder-delete"
        reclaimPolicy = "Delete"
        is_default    = false
        parameters    = {}
      })
    },
    {
      for f in fileset(path.module, "manifests/*.{yml,yaml}") : basename(f) => file("${path.module}/${f}")
    },
    var.manifests,
  )

  kube_apiserver_resources          = var.kube_apiserver_resources
  kube_scheduler_resources          = var.kube_scheduler_resources
  kube_controller_manager_resources = var.kube_controller_manager_resources
  etcd_resources                    = var.etcd_resources
  kube_proxy_resources = var.kube_proxy_resources

  ff_autoremove_agent = null
  ff_wait_ready       = var.ff_wait_ready
  ff_kubeproxy      = var.ff_kubeproxy
  cluster_cidr      = var.cluster_cidr
  service_cidr      = var.service_cidr
  extra_node_labels = var.extra_node_labels
}

module "agents" {
  source = "./node"

  for_each = {
    for agent in var.agents :
    agent.name => agent
  }

  name         = "${var.name}-${each.value.name}"
  is_server    = false
  is_first     = false
  is_persisted = false
  bootstrap    = false

  nodes_count      = each.value.nodes_count
  flavor_name      = each.value.flavor_name
  image_name       = each.value.image_name
  image_uuid       = each.value.image_uuid
  boot_volume_size = each.value.boot_volume_size
  boot_volume_type = each.value.boot_volume_type

  availability_zones = coalesce(each.value.availability_zones, [])
  group_id           = each.value.group_id != null ? each.value.group_id : openstack_compute_servergroup_v2.agents.id

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_string.rke2_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id    = openstack_networking_network_v2.net.id
  subnet_id     = openstack_networking_subnet_v2.agents.id
  secgroup_id   = openstack_networking_secgroup_v2.agent.id
  internal_vip  = local.internal_vip
  vip_interface = var.vip_interface
  bastion_host  = local.external_ip

  ff_autoremove_agent = var.ff_autoremove_agent
  ff_wait_ready       = var.ff_wait_ready
  ff_kubeproxy      = var.ff_kubeproxy
  cluster_cidr      = var.cluster_cidr
  service_cidr      = var.service_cidr
  extra_node_labels = var.extra_node_labels
}
