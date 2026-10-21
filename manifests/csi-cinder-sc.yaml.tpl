apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${name}
  annotations:
    %{~ if is_default ~}
    storageclass.kubernetes.io/is-default-class: "true"
    %{~ endif ~}
provisioner: cinder.csi.openstack.org
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
reclaimPolicy: ${reclaimPolicy}
# availability nova unless a class says otherwise: "" leaves the zone to the pod's node, as zoned regions need
parameters:
  %{~ for k, v in merge({ availability = "nova" }, parameters) ~}
  %{~ if v != "" ~}
  ${k}: ${v}
  %{~ endif ~}
  %{~ endfor ~}