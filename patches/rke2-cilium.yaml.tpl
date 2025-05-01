cluster:
  name: ${cluster_name}
  id: ${cluster_id}
eni:
  enabled: true
kubeProxyReplacement: "${ff_with_kubeproxy ? false : true}"
k8sServiceHost: 127.0.0.1
k8sServicePort: 6443
operator:
  replicas: ${operator_replica}
  nodeSelector:
    node-role.kubernetes.io/master: "true"
  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      memory: 128Mi
cni:
  chainingMode: "none"
resources:
  requests:
    cpu: 50m
    memory: 256Mi
  limits:
    memory: 512Mi
hubble:
  enabled: true
  metrics:
    enabled:
      - dns
      - drop
      - flow
      - flows-to-world
      - httpV2
      - icmp
      - kafka
      - port-distribution
      - tcp
  relay:
    enabled: true
    resources:
      requests:
        cpu: 25m
        memory: 128Mi
      limits:
        memory: 128Mi
