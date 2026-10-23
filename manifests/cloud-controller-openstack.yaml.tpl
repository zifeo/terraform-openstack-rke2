apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: openstack-cloud-controller-manager
  namespace: kube-system
spec:
  chart: openstack-cloud-controller-manager
  repo: https://kubernetes.github.io/cloud-provider-openstack
  # https://artifacthub.io/packages/helm/cloud-provider-openstack/openstack-cloud-controller-manager
  version: 2.37.1
  targetNamespace: kube-system
  bootstrap: true
  failurePolicy: retry
  forceConflicts: true
  valuesContent: |-
    logVerbosityLevel: 2
    # the node's resolvers, as before chart 2.37: on a new cluster CoreDNS waits for the nodes this controller
    # initializes, so it cannot resolve the identity endpoint through CoreDNS (ClusterFirstWithHostNet)
    dnsPolicy: Default
    nodeSelector:
      node-role.kubernetes.io/control-plane: "true"
    resources:
      requests:
        cpu: 25m
        memory: 64Mi
      limits:
        memory: 64Mi
    secret:
      enabled: true
      create: false
      name: rke2-occm-cloud-config
    controllerExtraArgs: |-
      - --use-service-account-credentials=false
    cluster:
      name: ${cluster_name}