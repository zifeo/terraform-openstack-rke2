resource "openstack_networking_secgroup_v2" "server" {
  name = "${var.name}-server"
}

resource "openstack_networking_secgroup_v2" "agent" {
  name = "${var.name}-agent"
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

resource "openstack_networking_secgroup_rule_v2" "inside" {
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
      # flannel VXLAN
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.server, "from" : openstack_networking_secgroup_v2.agent },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.server },
      { "port" : 8472, "protocol" : "udp", "to" : openstack_networking_secgroup_v2.agent, "from" : openstack_networking_secgroup_v2.agent },
      # kubelet / metric server
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

