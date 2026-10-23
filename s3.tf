resource "openstack_objectstorage_container_v1" "etcd_snapshots" {
  count = var.etcd_snapshots_in_object_store ? 1 : 0

  name          = "${var.name}-etcd-snapshots"
  region        = var.object_store_region
  force_destroy = true
}

# the container of the file-system backups Velero stopped making in 2024: forgotten, not destroyed, so that what it
# holds stays until its owner deletes it
removed {
  from = openstack_objectstorage_container_v1.restic

  lifecycle {
    destroy = false
  }
}

# Velero left the module for a stack of its own: its backups stay until their owner deletes them
removed {
  from = openstack_objectstorage_container_v1.velero

  lifecycle {
    destroy = false
  }
}

resource "openstack_identity_ec2_credential_v3" "s3" {
  count = var.etcd_snapshots_in_object_store ? 1 : 0
}

