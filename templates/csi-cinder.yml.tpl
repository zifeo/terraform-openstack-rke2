apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: openstack-cinder-csi
  namespace: kube-system
spec:
  chart: openstack-cinder-csi
  repo: https://kubernetes.github.io/cloud-provider-openstack
  version: 2.3.0
  targetNamespace: kube-system
  bootstrap: true
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
      snapshotController:
        enabled: true
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
          application-credential-name = ${app_name}
          application-credential-id = ${app_id}
          application-credential-secret = ${app_secret}
          region = ${region}
          tenant-id = ${project_id}
          [BlockStorage]
          ignore-volume-az = true
    storageClass:
      enabled: false
      custom: |
        
