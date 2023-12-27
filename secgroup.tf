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
      var.rules_ssh_cidr != null ? [{ "port" : 22, "protocol" : "tcp", "source" : var.rules_ssh_cidr }] : [],
      var.rules_k8s_cidr != null ? [{ "port" : 6443, "protocol" : "tcp", "source" : var.rules_k8s_cidr }] : [],
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
      { "port" : 22, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 22, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      # etcd
      { "port" : 2379, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 2380, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      # api server (k8s)
      { "port" : 6443, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 6443, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      # rke2 supervisor
      { "port" : 9345, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 9345, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      # cilium
      { "port" : 8472, "protocol" : "udp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 8472, "protocol" : "udp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 4240, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 4240, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 4240, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 4240, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 0, "protocol" : "icmp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 0, "protocol" : "icmp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 0, "protocol" : "icmp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 0, "protocol" : "icmp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.agent },
      # kubelet
      { "port" : 10250, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 10250, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.server },
      { "port" : 10250, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.server, "to" : openstack_networking_secgroup_v2.agent },
      { "port" : 10250, "protocol" : "tcp", "from" : openstack_networking_secgroup_v2.agent, "to" : openstack_networking_secgroup_v2.agent },
    ] :
    format("%s->%s-%s-%s", rule.from.name, rule.to.name, rule.protocol, rule.port) => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_group_id   = each.value.from.id
  security_group_id = each.value.to.id
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
  remote_group_id   = openstack_networking_secgroup_v2.server.id
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
  remote_group_id   = openstack_networking_secgroup_v2.server.id
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
  remote_group_id   = openstack_networking_secgroup_v2.agent.id
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
  remote_group_id   = openstack_networking_secgroup_v2.agent.id
  security_group_id = openstack_networking_secgroup_v2.agent.id
}
