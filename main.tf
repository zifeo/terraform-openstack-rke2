locals {
  s3 = var.etcd_snapshots_in_object_store ? {
    endpoint      = var.object_store_endpoint
    access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
    bucket        = openstack_objectstorage_container_v1.etcd_snapshots[0].name
    region        = var.object_store_region
    retention     = var.backup_retention
    # Swift's s3api has no policy that would narrow a key: the nodes' restores too
    restore_access_key    = openstack_identity_ec2_credential_v3.s3[0].access
    restore_access_secret = openstack_identity_ec2_credential_v3.s3[0].secret
  } : var.s3_backup

  # the module's, which cilium_values extends (variables.tf)
  cilium_values = yamldecode(templatefile("${path.module}/patches/rke2-cilium.yaml.tpl", {
    operator_replica = local.operator_replica
    cluster_name     = var.name
    cluster_id       = var.cluster_id
    kube_proxy       = var.kube_proxy
    nodeport_cidr    = var.subnet_agents_cidr
  }))

  # Cinder CSI's credentials, pushed to the servers with their secrets (node/secrets): the chart mounts the node's file
  cinder_credentials = templatefile("${path.module}/manifests/csi-cinder-credentials.conf.tpl", {
    auth_url   = var.identity_endpoint
    region     = openstack_identity_application_credential_v3.rke2.region
    project_id = openstack_identity_application_credential_v3.rke2.project_id
    app_id     = openstack_identity_application_credential_v3.rke2.id
    app_secret = openstack_identity_application_credential_v3.rke2.secret
    app_name   = openstack_identity_application_credential_v3.rke2.name
  })

  # what OCCM reads, applied through the API (hooks.tf)
  cluster_secrets = templatefile("${path.module}/manifests/cloud-config-secrets.yaml.tpl", {
    auth_url            = var.identity_endpoint
    region              = openstack_identity_application_credential_v3.rke2.region
    project_id          = openstack_identity_application_credential_v3.rke2.project_id
    app_id              = openstack_identity_application_credential_v3.rke2.id
    app_secret          = openstack_identity_application_credential_v3.rke2.secret
    app_name            = openstack_identity_application_credential_v3.rke2.name
    network_id          = openstack_networking_network_v2.net.id
    subnet_id           = openstack_networking_subnet_v2.agents.id
    floating_network_id = data.openstack_networking_network_v2.floating_net.id
    lb_provider         = var.lb_provider
    manage_sg           = var.security_groups
  })

  external_ip      = openstack_networking_floatingip_v2.floating_ip.address
  internal_vip     = var.subnet_servers_vip != null ? var.subnet_servers_vip : cidrhost(var.subnet_servers_cidr, 4)
  operator_replica = length(var.servers) > 1 ? 2 : 1
  # CoreDNS and metrics-server, on the agents only: one per untainted agent node, two at most
  agent_replica = min(2, sum(concat([0], [for a in var.agents : a.nodes_count if length(a.node_taints) == 0])))

  agent_taint_tolerations = {
    for a in var.agents : a.name => [
      for t in a.node_taints : merge(
        {
          key      = t.key
          effect   = t.effect
          operator = t.value != null ? "Equal" : "Exists"
        },
        t.value != null ? { value = t.value } : {}
      )
    ]
  }

  runtime_class_manifests = merge([for a in var.agents : {
    for name, rc in a.runtime_classes : "runtimeclass-${name}.yaml" => templatefile("${path.module}/manifests/runtimeclass.yaml.tpl", {
      name          = name
      handler       = rc.handler
      node_selector = a.node_labels
      tolerations   = local.agent_taint_tolerations[a.name]
    })
  }]...)

  agent_daemonset_tolerations_derived = distinct(concat(
    flatten(values(local.agent_taint_tolerations)),
    anytrue([for a in var.agents : try(a.gpu.enabled, false)]) ? [{
      key      = "nvidia.com/gpu"
      operator = "Exists"
      effect   = "NoSchedule"
    }] : []
  ))

  agent_daemonset_tolerations = (
    var.agent_daemonset_tolerations != null
    ? var.agent_daemonset_tolerations
    : local.agent_daemonset_tolerations_derived
  )
}

module "firewall" {
  source = "./firewall"

  subnet_servers_cidr = var.subnet_servers_cidr
  subnet_agents_cidr  = var.subnet_agents_cidr
  subnet_lb_cidr      = var.ff_lb_subnets_compat ? var.subnet_lb_cidr : null
  cluster_cidr        = var.cluster_cidr
  rules_ssh_cidr      = var.rules_ssh_cidr
  rules_k8s_cidr      = var.rules_k8s_cidr
  rules = {
    server_server = var.rules_server_server
    server_agent  = var.rules_server_agent
    agent_server  = var.rules_agent_server
    agent_agent   = var.rules_agent_agent
  }
}

resource "openstack_compute_servergroup_v2" "servers" {
  name     = "${var.name}-servers"
  policies = ["anti-affinity"]
}

resource "openstack_compute_servergroup_v2" "agents" {
  name     = "${var.name}-agents"
  policies = ["soft-anti-affinity"]

  # clusters before v6 named it -servers: Nova cannot rename a group, and a new one would replace every agent at once
  lifecycle {
    ignore_changes = [name]
  }
}

module "servers" {
  source = "./node"

  for_each = {
    for server in var.servers :
    server.name => server
  }

  name      = "${var.name}-${each.value.name}"
  is_server = true
  is_first  = var.servers[0].name == each.value.name
  # a single server keeps its rke2 volume across rebuilds, and starts the cluster alone every time; the first still
  # does while others are added to it
  is_persisted = length(var.servers) == 1 || (var.ff_grow_from_single_server && var.servers[0].name == each.value.name)
  bootstrap    = length(var.servers) == 1 ? true : var.bootstrap

  nodes_count        = 1
  flavor_name        = each.value.flavor_name
  image_name         = each.value.image_name
  image_uuid         = each.value.image_uuid
  image_prebuilt     = each.value.image_prebuilt
  boot_volume_size   = each.value.boot_volume_size
  boot_volume_type   = each.value.boot_volume_type
  registries         = var.registries
  cinder_credentials = local.cinder_credentials

  availability_zones = coalesce(each.value.availability_zones, [])
  group_id           = each.value.group_id != null ? each.value.group_id : openstack_compute_servergroup_v2.servers.id

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_password.rke2_token.result
  rke2_agent_token   = random_password.rke2_agent_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  s3               = local.s3
  backup_schedule  = var.backup_schedule
  backup_retention = var.backup_retention

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id = openstack_networking_network_v2.net.id
  # through the router's interface: a node that boots before its subnet is routed has no internet for cloud-init
  subnet_id    = openstack_networking_router_interface_v2.servers.subnet_id
  cluster_cidr = var.cluster_cidr
  service_cidr = var.service_cidr
  secgroup_id  = var.security_groups ? openstack_networking_secgroup_v2.server[0].id : null
  internal_vip = local.internal_vip
  san          = distinct(concat([local.external_ip, local.internal_vip], var.additional_san))

  host_key         = local.servers_host_key
  bastion_host     = local.external_ip
  bastion_user     = var.servers[0].system_user
  vip_port_id      = openstack_networking_port_v2.dummy.id
  bastion_host_key = local.servers_host_key.public
  firewall         = module.firewall.ufw.server

  manifests_folder = var.manifests_folder
  manifests = merge(
    {
      "cinder-csi.yaml" : templatefile("${path.module}/manifests/csi-cinder.yaml.tpl", {
        operator_replica        = local.operator_replica
        node_plugin_tolerations = local.agent_daemonset_tolerations
      }),
      "cloud-controller-openstack.yaml" : templatefile("${path.module}/manifests/cloud-controller-openstack.yaml.tpl", {
        cluster_name = var.name
      }),
      # local.cilium_values renders patches/rke2-cilium.yaml.tpl; cilium_values adds keys the module leaves to the
      # chart and may not repeat one of them (variables.tf)
      "patches/rke2-cilium.yaml" : yamlencode(merge(local.cilium_values, var.cilium_values)),
      "patches/rke2-coredns.yaml" : templatefile("${path.module}/patches/rke2-coredns.yaml.tpl", {
        agent_replica = local.agent_replica
      }),
      "patches/rke2-metrics-server.yaml" : templatefile("${path.module}/patches/rke2-metrics-server.yaml.tpl", {
        agent_replica = local.agent_replica
      }),
    },
    {
      for c in var.storage_classes : "${c.name}.yaml" => templatefile("${path.module}/manifests/csi-cinder-sc.yaml.tpl", {
        name          = c.name
        reclaimPolicy = c.reclaim_policy
        is_default    = c.default
        parameters    = c.parameters
      })
    },
    {
      for f in fileset(path.module, "manifests/*.{yml,yaml}") : basename(f) => file("${path.module}/${f}")
      if basename(f) != "runtimeclass-nvidia.yaml"
    },
    anytrue([for a in var.agents : try(a.gpu.enabled && a.gpu.runtime_class, false)]) ? {
      "runtimeclass-nvidia.yaml" = file("${path.module}/manifests/runtimeclass-nvidia.yaml")
    } : {},
    local.runtime_class_manifests,
    var.manifests,
  )

  kube_apiserver_resources          = var.kube_apiserver_resources
  kube_scheduler_resources          = var.kube_scheduler_resources
  kube_controller_manager_resources = var.kube_controller_manager_resources
  etcd_resources                    = var.etcd_resources
  kube_proxy_resources              = var.kube_proxy_resources

  kubelet_config        = var.kubelet_config
  agent_removal_timeout = null
  kube_proxy            = var.kube_proxy
  nodeport_cidr         = var.subnet_agents_cidr

  ff_wait_ready      = var.ff_wait_ready
  ff_gateway_api_crd = var.ff_gateway_api_crd

  node_taints     = each.value.node_taints
  node_labels     = each.value.node_labels
  gpu             = {}
  runtime_classes = {}
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
  image_prebuilt   = each.value.image_prebuilt
  boot_volume_size = each.value.boot_volume_size
  boot_volume_type = each.value.boot_volume_type
  registries       = var.registries
  # agents get no OpenStack credential: their Cinder node plugin needs none
  cinder_credentials = null

  availability_zones = coalesce(each.value.availability_zones, [])
  group_id           = each.value.group_id != null ? each.value.group_id : openstack_compute_servergroup_v2.agents.id

  rke2_version       = each.value.rke2_version
  rke2_config        = each.value.rke2_config
  rke2_token         = random_password.rke2_agent_token.result
  rke2_volume_size   = each.value.rke2_volume_size
  rke2_volume_type   = each.value.rke2_volume_type
  rke2_volume_device = each.value.rke2_volume_device

  system_user         = each.value.system_user
  keypair_name        = openstack_compute_keypair_v2.key.name
  ssh_authorized_keys = local.ssh_authorized_keys

  network_id   = openstack_networking_network_v2.net.id
  subnet_id    = openstack_networking_router_interface_v2.agents.subnet_id
  cluster_cidr = var.cluster_cidr
  service_cidr = var.service_cidr
  secgroup_id  = var.security_groups ? openstack_networking_secgroup_v2.agent[0].id : null
  firewall     = module.firewall.ufw.agent
  internal_vip = local.internal_vip

  bastion_host     = local.external_ip
  bastion_user     = var.servers[0].system_user
  vip_port_id      = null
  bastion_host_key = local.servers_host_key.public

  kubelet_config        = var.kubelet_config
  agent_removal_timeout = var.agent_removal_timeout
  kube_proxy            = var.kube_proxy
  nodeport_cidr         = var.subnet_agents_cidr

  ff_wait_ready      = var.ff_wait_ready
  ff_gateway_api_crd = var.ff_gateway_api_crd

  node_taints     = each.value.node_taints
  node_labels     = each.value.node_labels
  gpu             = each.value.gpu
  runtime_classes = each.value.runtime_classes
}
