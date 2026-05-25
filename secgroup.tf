resource "openstack_networking_secgroup_v2" "server" {
  name                 = "${var.name}-server"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_v2" "agent" {
  name                 = "${var.name}-agent"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "server_outside4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "server_outside6" {
  direction         = "egress"
  ethertype         = "IPv6"
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_outside4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_outside6" {
  direction         = "egress"
  ethertype         = "IPv6"
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "outside_servers" {
  for_each = {
    for rule in concat(
      var.rules_ssh_cidr != null ? [for r in var.rules_ssh_cidr : { "port" : 22, "protocol" : "tcp", "source" : r }] : [],
      var.rules_k8s_cidr != null ? [for r in var.rules_k8s_cidr : { "port" : 6443, "protocol" : "tcp", "source" : r }] : [],
    ) :
    format("%s-%s-%s", rule["source"], rule["protocol"], rule["port"]) => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.source
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "default" {
  for_each = {
    for rule in [
      # bastion ssh
      { "port" : 22, "protocol" : "tcp", "from" : "server", "to" : "agent" },
      { "port" : 22, "protocol" : "tcp", "from" : "server", "to" : "server" },
      # etcd
      { "port" : 2379, "protocol" : "tcp", "from" : "server", "to" : "server" },
      { "port" : 2380, "protocol" : "tcp", "from" : "server", "to" : "server" },
      # api server (k8s)
      { "port" : 6443, "protocol" : "tcp", "from" : "server", "to" : "server" },
      { "port" : 6443, "protocol" : "tcp", "from" : "agent", "to" : "server" },
      # rke2 supervisor
      { "port" : 9345, "protocol" : "tcp", "from" : "server", "to" : "server" },
      { "port" : 9345, "protocol" : "tcp", "from" : "agent", "to" : "server" },
      # cilium
      { "port" : 8472, "protocol" : "udp", "from" : "server", "to" : "server" },
      { "port" : 8472, "protocol" : "udp", "from" : "agent", "to" : "server" },
      { "port" : 8472, "protocol" : "udp", "from" : "server", "to" : "agent" },
      { "port" : 8472, "protocol" : "udp", "from" : "agent", "to" : "agent" },
      { "port" : 4240, "protocol" : "tcp", "from" : "server", "to" : "server" },
      { "port" : 4240, "protocol" : "tcp", "from" : "agent", "to" : "server" },
      { "port" : 4240, "protocol" : "tcp", "from" : "server", "to" : "agent" },
      { "port" : 4240, "protocol" : "tcp", "from" : "agent", "to" : "agent" },
      { "port" : 0, "protocol" : "icmp", "from" : "server", "to" : "server" },
      { "port" : 0, "protocol" : "icmp", "from" : "agent", "to" : "server" },
      { "port" : 0, "protocol" : "icmp", "from" : "server", "to" : "agent" },
      { "port" : 0, "protocol" : "icmp", "from" : "agent", "to" : "agent" },
      # kubelet
      { "port" : 10250, "protocol" : "tcp", "from" : "server", "to" : "server" },
      { "port" : 10250, "protocol" : "tcp", "from" : "agent", "to" : "server" },
      { "port" : 10250, "protocol" : "tcp", "from" : "server", "to" : "agent" },
      { "port" : 10250, "protocol" : "tcp", "from" : "agent", "to" : "agent" },
    ] :
    format("%s->%s-%s-%s", rule.from, rule.to, rule.protocol, rule.port) => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.from == "server" ? var.subnet_servers_cidr : var.subnet_agents_cidr
  security_group_id = each.value.to == "server" ? openstack_networking_secgroup_v2.server.id : openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "server_server" {
  for_each = {
    for rule in var.rules_server_server :
    format("%s-%s%s", rule["protocol"], rule["port"], rule["name"] != null ? "-${rule["name"]}" : "") => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = var.subnet_servers_cidr
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "server_agent" {
  for_each = {
    for rule in var.rules_server_agent :
    format("%s-%s%s", rule["protocol"], rule["port"], rule["name"] != null ? "-${rule["name"]}" : "") => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = var.subnet_servers_cidr
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_server" {
  for_each = {
    for rule in var.rules_agent_server :
    format("%s-%s%s", rule["protocol"], rule["port"], rule["name"] != null ? "-${rule["name"]}" : "") => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = var.subnet_agents_cidr
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "agent_agent" {
  for_each = {
    for rule in var.rules_agent_agent :
    format("%s-%s%s", rule["protocol"], rule["port"], rule["name"] != null ? "-${rule["name"]}" : "") => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = var.subnet_agents_cidr
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "legacy_lb_to_agent" {
  count             = var.ff_lb_subnets_compat ? 1 : 0
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_ip_prefix  = var.subnet_lb_cidr
  security_group_id = openstack_networking_secgroup_v2.agent.id
}
