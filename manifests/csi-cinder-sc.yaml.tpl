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
parameters:
  availability: nova
  %{~ for k, v in parameters ~}
  ${k}: ${v}
  %{~ endfor ~}