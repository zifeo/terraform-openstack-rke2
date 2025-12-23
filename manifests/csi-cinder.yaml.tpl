apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: openstack-cinder-csi
  namespace: kube-system
spec:
  chart: openstack-cinder-csi
  repo: https://kubernetes.github.io/cloud-provider-openstack
  version: 2.34.1
  targetNamespace: kube-system
  bootstrap: true
  valuesContent: |-
    csi:
      attacher:
        resources:
          requests:
            cpu: 20m
            memory: 32M
          limits:
      provisioner:
        topology: "true"
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
            cpu: 10m
            memory: 16M
          limits:
            memory: 32M
      nodeDriverRegistrar:
        resources:
          requests:
            cpu: 10m
            memory: 16M
          limits:
            memory: 32M
      plugin:
        nodePlugin:
          tolerations: []
        controllerPlugin:
          replicas: ${operator_replica}
          nodeSelector:
            node-role.kubernetes.io/control-plane: "true"
          affinity:
            podAntiAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchLabels:
                      app: openstack-cinder-csi
                      component: controllerplugin
                  topologyKey: kubernetes.io/hostname
          tolerations:
            - key: node-role.kubernetes.io/control-plane
              effect: NoSchedule
        resources:
          requests:
            cpu: 25m
            memory: 128Mi
          limits:
            memory: 256Mi
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
          rescan-on-resize = true
    storageClass:
      enabled: false
    logVerbosityLevel: 5
