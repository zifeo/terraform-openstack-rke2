resource "openstack_objectstorage_container_v1" "etcd_snapshots" {
  count = var.ff_native_backup != "" ? 1 : 0

  name          = "${var.name}-etcd-snapshots"
  force_destroy = true
}

resource "openstack_identity_ec2_credential_v3" "s3" {
  count = var.ff_native_backup != "" ? 1 : 0
}

