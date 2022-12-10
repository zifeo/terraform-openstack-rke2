resource "openstack_networking_secgroup_v2" "server" {
  name                 = "${var.name}-server"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_v2" "agent" {
  name                 = "${var.name}-agent"
  delete_default_rules = true
}

resource "openstack_networking_secgroup_rule_v2" "ext" {
  for_each = {
    for rule in var.rules_ext :
    format("%s-%s-%s%s", rule["source"], rule["protocol"], rule["port"], rule["name"] != null ? "-${rule["name"]}" : "") => rule
  }
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = each.value.protocol
  port_range_min    = each.value.port
  port_range_max    = each.value.port
  remote_ip_prefix  = each.value.source
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "server4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "server6" {
  direction         = "egress"
  ethertype         = "IPv6"
  security_group_id = openstack_networking_secgroup_v2.server.id
}

resource "openstack_networking_secgroup_rule_v2" "agent4" {
  direction         = "egress"
  ethertype         = "IPv4"
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "agent6" {
  direction         = "egress"
  ethertype         = "IPv6"
  security_group_id = openstack_networking_secgroup_v2.agent.id
}

resource "openstack_networking_secgroup_rule_v2" "default" {
  for_each = {
    for rule in [
      # bastion ssh
      { "port" : 22, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      # etcd
      { "port" : 2379, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 2380, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      # api server
      { "port" : 6443, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 6443, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      # rke2 supervisor
      { "port" : 9345, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 9345, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      # cilium
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 4240, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 4240, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 4240, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 4240, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 0, "protocol" : "icmp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 0, "protocol" : "icmp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 0, "protocol" : "icmp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 0, "protocol" : "icmp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.agent },
      # kubelet
      { "port" : 10250, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 10250, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 10250, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 10250, "protocol" : "tcp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.agent },
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

resource "openstack_networking_secgroup_rule_v2" "vrrp_broadcast" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "vrrp"
  remote_group_id   = openstack_networking_secgroup_v2.server.id
  security_group_id = openstack_networking_secgroup_v2.server.id
}
