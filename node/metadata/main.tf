# What a node says of itself and what it lets in, without any resource: its instance metadata, which a plan shows and
# the rke2-pro CLI reads, and its config, which tofu pushes over SSH (../hooks.tf) for rke2-node-config to apply.
# tests/cloud-init renders both too, so that the e2e serves and pushes its VMs the same.
variable "rke2_version" {
  type = string
}

variable "role" {
  type = string
}

variable "bootstrap" {
  type = bool
}

variable "ssh_authorized_keys" {
  type        = list(string)
  description = "Keys besides the instance's keypair"
}

variable "firewall" {
  type = list(object({
    protocol = string
    port     = string
    from     = string
  }))
  description = "What UFW lets in (../firewall): protocol tcp, udp or any, port a number, a range a:b or any, a source CIDR"
}

output "metadata" {
  value = {
    rke2_version = var.rke2_version
    rke2_role    = var.role
    # the plan only shows a hash of user_data: this tells a rolling replacement that the node would start a new cluster
    rke2_bootstrap = tostring(var.bootstrap)
  }
}

# /etc/rancher/rke2-node-config.json: not in the instance metadata, which another node could answer for without port
# security
output "config" {
  value = jsonencode({
    ssh_keys = [for k in var.ssh_authorized_keys : trimspace(k)]
    firewall = [for r in var.firewall : "${r.protocol} ${r.port} ${r.from}"]
  })

  # what rke2-node-config accepts: a key and its comment, no options
  precondition {
    condition = alltrue([for k in var.ssh_authorized_keys : can(regex(
      "^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\\.com|sk-ecdsa-sha2-nistp256@openssh\\.com) [A-Za-z0-9+/]+={0,2}( [^\\x00-\\x1f\\x7f]*)?$",
      trimspace(k)
    ))])
    error_message = "ssh_authorized_keys besides the first must each be one public key and its comment, without options."
  }
}
