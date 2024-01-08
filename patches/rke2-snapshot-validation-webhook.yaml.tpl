
nodeSelector:
  node-role.kubernetes.io/master: "true"
tolerations:
  - effect: NoExecute
    key: CriticalAddonsOnly
    operator: "Exists"
