apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: rke2-cilium
  namespace: kube-system
spec:
  valuesContent: |-
    cluster:
      name: ${cluster_name}
      id: ${cluster_id}
    eni:
      enabled: true
    kubeProxyReplacement: strict
    k8sServiceHost: ${apiserver_host}
    k8sServicePort: 6443
    operator:
      replicas: 2
      nodeSelector:
        node-role.kubernetes.io/master: "true"
      tolerations:
        - effect: NoExecute
          key: CriticalAddonsOnly
          operator: "Exists"
    cni:
      chainingMode: "none"
    resources: {}
      # limits:
      #   cpu: 4000m
      #   memory: 4Gi
      # requests:
      #   cpu: 100m
      #   memory: 512Mi

