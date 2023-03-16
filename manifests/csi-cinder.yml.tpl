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
        image:
          repository: k8s.gcr.io/sig-storage/csi-attacher
          tag: v4.0.0
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      provisioner:
        topology: "true"
        image:
          repository: k8s.gcr.io/sig-storage/csi-provisioner
          tag: v3.4.0
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      snapshotter:
        image:
          repository: k8s.gcr.io/sig-storage/csi-snapshotter
          tag: v6.1.0
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      resizer:
        image:
          repository: k8s.gcr.io/sig-storage/csi-resizer
          tag: v1.6.0
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      livenessprobe:
        image:
          repository: k8s.gcr.io/sig-storage/livenessprobe
          tag: v2.8.0
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      nodeDriverRegistrar:
        image:
          repository: k8s.gcr.io/sig-storage/csi-node-driver-registrar
          tag: v2.6.2
          pullPolicy: IfNotPresent
        resources:
          requests:
            cpu: 20m
            memory: 32M
      plugin:
        image:
          repository: docker.io/k8scloudprovider/cinder-csi-plugin
          tag: "v1.26.2"
          pullPolicy: IfNotPresent
        nodePlugin:
          tolerations: []
        controllerPlugin:
          replicas: ${operator_replica}
          nodeSelector:
            node-role.kubernetes.io/master: "true"
          affinity:
            podAntiAffinity:
              requiredDuringSchedulingIgnoredDuringExecution:
                - labelSelector:
                    matchLabels:
                      app: openstack-cinder-csi
                      component: controllerplugin
                  topologyKey: kubernetes.io/hostname
          tolerations:
            - effect: NoExecute
              key: CriticalAddonsOnly
              operator: "Exists"
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
