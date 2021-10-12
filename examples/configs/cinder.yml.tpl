apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cinder-csi-plugin
  namespace: kube-system
spec:
  chart: openstack-cinder-csi
  repo: https://kubernetes.github.io/cloud-provider-openstack
  targetNamespace: kube-system
  bootstrap: True
  valuesContent: |-
    secret:
      enabled: true
      create: true
      name: cinder-csi-cloud-config
      data:
        cloud-config: |-
          [Global]
          auth-url=${auth_url}
          application-credential-id=${app_id}
          application-credential-secret=${app_secret}
          region=${region}
          tenant-id=${project_id}
          [BlockStorage]
          ignore-volume-az = yes
    storageClass:
      enabled: false
      custom: |-
        apiVersion: storage.k8s.io/v1
        kind: StorageClass
        metadata:
          annotations: {}
          name: csi-cinder-delete
        provisioner: cinder.csi.openstack.org
        volumeBindingMode: WaitForFirstConsumer
        allowVolumeExpansion: true
        reclaimPolicy: Delete
        parameters:
          availability: nova
        ---
        apiVersion: storage.k8s.io/v1
        kind: StorageClass
        metadata:
          annotations:
            storageclass.kubernetes.io/is-default-class: "true"
          name: csi-cinder-retain
        provisioner: cinder.csi.openstack.org
        volumeBindingMode: WaitForFirstConsumer
        allowVolumeExpansion: true
        reclaimPolicy: Retain
        parameters:
          availability: nova
