apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  chart: kube-vip
  repo: "https://kube-vip.github.io/helm-charts"
  version: 0.4.4
  targetNamespace: kube-system
  bootstrap: true
  valuesContent: |-
    image:
      repository: ghcr.io/kube-vip/kube-vip
      pullPolicy: IfNotPresent
      tag: "v0.6.2"

    config:
      address: ${vip_address}

    env:
      vip_interface: ens3
      vip_arp: "true"
      lb_enable: "true"
      lb_port: "6443"
      vip_cidr: "32"
      cp_enable: "true"
      cp_namespace: "kube-system"
      vip_ddns: "false"
      svc_enable: "false"
      svc_election: "false"
      vip_leaderelection: "true"

    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        memory: 256Mi

    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: Exists
      - effect: NoSchedule
        key: node.cloudprovider.kubernetes.io/uninitialized
        operator: "Exists"