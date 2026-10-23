cluster:
  name: ${cluster_name}
  id: ${cluster_id}
enableIPv4Masquerade: true
kubeProxyReplacement: ${kube_proxy ? "false" : "true"}
k8sServiceHost: 127.0.0.1
k8sServicePort: 6443
# node ports on the agents' addresses only, where the load balancers reach them: Cilium serves them before netfilter,
# so UFW never filters them, and the floating IP leads to the VIP
nodePort:
  addresses:
    - ${nodeport_cidr}
socketLB:
  # required by sandboxed runtimes like gVisor, whose own network stack never reaches the socket hooks that
  # translate Services
  hostNamespaceOnly: true
operator:
  replicas: ${operator_replica}
  # maxUnavailable 1, the chart's: two drains at once never take every operator
  podDisruptionBudget:
    enabled: true
  nodeSelector:
    node-role.kubernetes.io/control-plane: "true"
  resources:
    requests:
      cpu: 50m
      memory: 256Mi
    limits:
      memory: 384Mi
cni:
  chainingMode: "none"
resources:
  requests:
    cpu: 50m
    memory: 256Mi
  limits:
    memory: 512Mi
