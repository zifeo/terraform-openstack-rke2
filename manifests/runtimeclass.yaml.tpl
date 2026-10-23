apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: ${name}
handler: ${handler}
scheduling:
  nodeSelector: ${jsonencode(node_selector)}
  tolerations: ${jsonencode(tolerations)}
