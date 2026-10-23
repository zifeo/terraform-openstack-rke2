apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: openstack-cinder-csi
  namespace: kube-system
spec:
  chart: openstack-cinder-csi
  repo: https://kubernetes.github.io/cloud-provider-openstack
  # https://artifacthub.io/packages/helm/cloud-provider-openstack/openstack-cinder-csi
  version: 2.37.1
  targetNamespace: kube-system
  bootstrap: true
  failurePolicy: retry
  forceConflicts: true
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
          tolerations:
            ${indent(12, yamlencode(node_plugin_tolerations))}
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
    # the node's /etc/config/cloud.conf: the credentials on the servers only, where the controller runs. The chart
    # gives both plugins the same Secret, which would put them on every agent
    secret:
      enabled: false
      hostMount: true
    storageClass:
      enabled: false
    logVerbosityLevel: 5
