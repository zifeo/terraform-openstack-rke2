apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: 6.0.0
  targetNamespace: velero
  valuesContent: |-
    image:
      repository: velero/velero
      tag: v1.13.0
      pullPolicy: IfNotPresent
    initContainers:
      - name: velero-plugin-for-openstack
        image: lirt/velero-plugin-for-openstack:v0.7.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
      - name: velero-plugin-for-csi
        image: velero/velero-plugin-for-csi:v0.7.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
    tolerations:
      - effect: NoExecute
        key: CriticalAddonsOnly
        operator: "Exists"
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: null
        memory: 256Mi
    kubectl:
      image:
        repository: docker.io/bitnamilegacy/kubectl
        tag: "1.29-debian-11"
    configuration:
      namespace: velero
      features: EnableCSI
      defaultBackupTTL: 72h
      backupStorageLocation:
        - name: default
          provider: community.openstack.org/openstack
          bucket: ${bucket_velero}
          config:
            cloud: self
            region: ${region}
      volumeSnapshotLocation:
        - name: default
          provider: csi
      extraEnvVars:
        OS_AUTH_URL: ${auth_url}/v3
        OS_APPLICATION_CREDENTIAL_ID: ${app_id}
        OS_APPLICATION_CREDENTIAL_NAME: ${app_name}
        OS_APPLICATION_CREDENTIAL_SECRET: ${app_secret}
        # for community.openstack.org/openstack (env vars do not work and take precedence over clouds.yaml unless cloud set)
        OS_CLOUD: self
    credentials:
      # for community.openstack.org/openstack
      secretContents:
        clouds.yaml: |
          clouds:
            self:
              region_name: ${region}
              auth:
                auth_url: ${auth_url}/v3
                application_credential_id: ${app_id}
                application_credential_name: ${app_name}
                application_credential_secret: ${app_secret}
    extraVolumes:
      - name: cloud-config-velero
        secret:
          secretName: velero
          items:
          - key: clouds.yaml
            path: clouds.yaml
    extraVolumeMounts:
      - name: cloud-config-velero
        mountPath: /etc/openstack/clouds.yaml
        readOnly: true
        subPath: clouds.yaml
    backupsEnabled: true
    snapshotsEnabled: true
    deployNodeAgent: true
    nodeAgent:
      podVolumePath: /var/lib/kubelet/pods
      containerSecurityContext:
        privileged: false
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: null
          memory: null
