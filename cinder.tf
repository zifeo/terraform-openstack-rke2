
resource "openstack_identity_application_credential_v3" "rke2_csi" {
  name = "${var.name}-csi-credentials"
}

