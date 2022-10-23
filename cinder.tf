
resource "openstack_identity_application_credential_v3" "rke2_csi" {
  count = var.ff_native_csi != "" ? 1 : 0

  name = "${var.name}-csi-credentials"
}

