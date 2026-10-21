# What the nodes let in, without any resource: the security groups' rules between nodes (../secgroup.tf), and UFW's
# on every node, which allows what the security groups do and filters alone without port security. tests/cloud-init
# renders it too, so that the e2e serves its VMs the same rules.

variable "subnet_servers_cidr" {
  type = string
}

variable "subnet_agents_cidr" {
  type = string
}

variable "subnet_lb_cidr" {
  type        = string
  description = "null without the legacy load balancers' subnet"
}

variable "cluster_cidr" {
  type = string
}

variable "rules_ssh_cidr" {
  type = list(string)
}

variable "rules_k8s_cidr" {
  type        = list(string)
  description = "null: no API from outside"
}

variable "rules" {
  type = map(list(object({
    port     = number
    protocol = string
  })))
  description = "The extra rules between nodes, by from_to (server_server, server_agent, agent_server, agent_agent)"
}

locals {
  # between nodes, by role
  default_node_rules = [
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
    # cilium wireguard (cilium_values.encryption), open either way: agents keep encrypting until their cilium restarts
    { "port" : 51871, "protocol" : "udp", "from" : "server", "to" : "server" },
    { "port" : 51871, "protocol" : "udp", "from" : "agent", "to" : "server" },
    { "port" : 51871, "protocol" : "udp", "from" : "server", "to" : "agent" },
    { "port" : 51871, "protocol" : "udp", "from" : "agent", "to" : "agent" },
  ]
  node_rules = concat(local.default_node_rules, flatten([
    for from_to, rules in var.rules : [
      for r in rules : { "port" : r.port, "protocol" : r.protocol, "from" : split("_", from_to)[0], "to" : split("_", from_to)[1] }
    ]
  ]))
  subnet = { server = var.subnet_servers_cidr, agent = var.subnet_agents_cidr }
}

output "default_node_rules" {
  value = local.default_node_rules
}

# ICMP is UFW's default. The node ports are for the cloud controller's load balancers, in the agents' subnet (or the
# legacy one), and pods reach the nodes: a server's supervisor and etcd excepted, which no pod speaks to.
output "ufw" {
  value = { for role in ["server", "agent"] : role => concat(
    [for r in local.node_rules : { protocol = r.protocol, port = tostring(r.port), from = local.subnet[r.from] } if r.to == role && r.protocol != "icmp"],
    role == "server" ? concat(
      [for c in var.rules_ssh_cidr : { protocol = "tcp", port = "22", from = c }],
      [for c in coalesce(var.rules_k8s_cidr, []) : { protocol = "tcp", port = "6443", from = c }],
    ) : [],
    flatten([for s in compact([var.subnet_agents_cidr, var.subnet_lb_cidr]) : [
      for p in ["tcp", "udp"] : { protocol = p, port = "30000:32767", from = s }
    ]]),
    role == "server" ? concat(
      [for p in ["1:2378", "2381:9344", "9346:65535"] : { protocol = "tcp", port = p, from = var.cluster_cidr }],
      [{ protocol = "udp", port = "1:65535", from = var.cluster_cidr }],
    ) : [{ protocol = "any", port = "any", from = var.cluster_cidr }],
  ) }

  precondition {
    condition     = alltrue([for f, _ in var.rules : contains(["server_server", "server_agent", "agent_server", "agent_agent"], f)])
    error_message = "rules are keyed by server_server, server_agent, agent_server or agent_agent."
  }

  # anything else would pass the plan, then stop rke2-node-config, and cloud-init with it, on every node
  precondition {
    condition = alltrue([for r in flatten(values(var.rules)) :
      r.protocol == "icmp" || (contains(["tcp", "udp"], r.protocol) && r.port >= 1 && r.port <= 65535)
    ])
    error_message = "rules_* are tcp or udp with a port from 1 to 65535, or icmp: what both the security groups and UFW take."
  }
}
