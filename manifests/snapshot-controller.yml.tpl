apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: snapshot-controller
  namespace: kube-system
spec:
  chart: snapshot-controller
  repo: https://piraeus.io/helm-charts
  version: 1.6.2
  targetNamespace: kube-system
  bootstrap: True
  valuesContent: |-
    image:
      repository: registry.k8s.io/sig-storage/snapshot-controller
      tag: v6.2.1
      pullPolicy: IfNotPresent
    replicaCount: ${operator_replica}
    nodeSelector:
      node-role.kubernetes.io/master: "true"
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: snapshot-controller
            topologyKey: kubernetes.io/hostname
    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
    resources:
      requests:
        cpu: 50m
        memory: 64Mi
