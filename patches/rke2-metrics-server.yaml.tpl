# metrics-server's own high-availability manifest, which the autoscalers reading it need through a drain: two replicas
# on two nodes. Its chart tolerates no taint, so the agents only
replicas: ${agent_replica}
updateStrategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 0
    maxUnavailable: 1
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: rke2-metrics-server
        topologyKey: kubernetes.io/hostname
# maxUnavailable rather than upstream's minAvailable 1, which would block a single replica's drain for good
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1
