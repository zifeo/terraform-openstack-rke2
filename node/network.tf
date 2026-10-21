# The floating IP, on the VIP from the start: before the cluster exists, the first server holds the VIP itself until
# rke2 starts kube-vip (cloud-init.yaml.tpl, rke2-vip-claim), so that tofu reaches it through this IP to push the
# secrets rke2 waits for. Here, not at the root, so that the push through it waits for it.
resource "openstack_networking_floatingip_associate_v2" "fip" {
  count       = var.is_first ? 1 : 0
  floating_ip = var.bastion_host
  port_id     = var.vip_port_id
}

moved {
  from = openstack_networking_floatingip_associate_v2.bootstrap
  to   = openstack_networking_floatingip_associate_v2.fip
}
