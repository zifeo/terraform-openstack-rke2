resource "openstack_objectstorage_container_v1" "etcd_snapshots" {
  count = var.ff_native_backup ? 1 : 0

  name          = "${var.name}-etcd-snapshots"
  region        = var.object_store_region
  force_destroy = true
}

resource "openstack_objectstorage_container_v1" "restic" {
  name          = "${var.name}-restic"
  region        = var.object_store_region
  force_destroy = true
}

resource "openstack_objectstorage_container_v1" "velero" {
  name          = "${var.name}-velero"
  region        = var.object_store_region
  force_destroy = true
}

resource "openstack_identity_ec2_credential_v3" "s3" {
  count = var.ff_native_backup ? 1 : 0
}

