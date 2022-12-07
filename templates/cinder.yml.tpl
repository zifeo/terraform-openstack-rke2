apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: cinder-csi-plugin
  namespace: kube-system
spec:
  chart: openstack-cinder-csi
  repo: https://kubernetes.github.io/cloud-provider-openstack
  version: 2.3.0
  targetNamespace: kube-system
  bootstrap: True
  valuesContent: |-
    csi:
      attacher:
        resources:
          requests:
            cpu: 20m
            memory: 32M
      provisioner:
        resources:
          requests:
            cpu: 20m
            memory: 32M
      snapshotter:
        resources:
          requests:
            cpu: 20m
            memory: 32M
      resizer:
        resources:
          requests:
            cpu: 20m
            memory: 32M
      livenessprobe:
        resources:
          requests:
            cpu: 20m
            memory: 32M
      plugin:
        resources:
          requests:
            cpu: 20m
            memory: 32M
    secret:
      enabled: true
      create: true
      name: cinder-csi-cloud-config
      data:
        cloud.conf: |-
          [Global]
          auth-url = ${auth_url}
          application-credential-id = ${app_id}
          application-credential-secret = ${app_secret}
          region = ${region}
          tenant-id = ${project_id}
          [BlockStorage]
          ignore-volume-az = true
    storageClass:
      enabled: true
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
