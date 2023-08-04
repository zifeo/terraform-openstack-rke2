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
      replicas: ${operator_replica}
      nodeSelector:
        node-role.kubernetes.io/master: "true"
      tolerations:
        - effect: NoExecute
          key: CriticalAddonsOnly
          operator: "Exists"
        - effect: NoSchedule
          key: node.cloudprovider.kubernetes.io/uninitialized
          operator: "Exists"
      requests:
        cpu: 50m
        memory: 64Mi
    cni:
      chainingMode: "none"
    resources: 
      requests:
        cpu: 50m
        memory: 128Mi
    hubble:
      enabled: true
      metrics:
        enabled:
          - dns
          - drop
          - flow
          - flows-to-world
          - httpV2
          - port-distribution
          - tcp
          - icmp
      relay:
        enabled: true
        resources:
          requests:
            cpu: 25m
            memory: 128Mi
          limits:
            memory: 128Mi
