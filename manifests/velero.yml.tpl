apiVersion: helm.cattle.io/v1
kind: HelmChart
metadata:
  name: velero
  namespace: kube-system
spec:
  chart: velero
  repo: https://vmware-tanzu.github.io/helm-charts
  version: 2.32.4
  targetNamespace: kube-system
  bootstrap: true
  valuesContent: |-
    initContainers:
      - name: velero-plugin-for-openstack
        image: lirt/velero-plugin-for-openstack:v0.4.1
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins
      - name: velero-plugin-for-csi
        image: velero/velero-plugin-for-csi:v0.4.0
        imagePullPolicy: IfNotPresent
        volumeMounts:
          - mountPath: /target
            name: plugins

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        memory: 256Mi

    configuration:
      provider: mixed

      backupStorageLocation:
        provider: community.openstack.org/openstack
        bucket: backup
        config:
          cloud: self
          region: us-east-1
          resticRepoPrefix: swift:restic:/
        extraEnvVars:
          OS_AUTH_URL: ${auth_url}
          OS_APPLICATION_CREDENTIAL_NAME: ${app_name}
          OS_APPLICATION_CREDENTIAL_ID: ${app_id}
          OS_APPLICATION_CREDENTIAL_SECRET: ${app_secret}

      volumeSnapshotLocation:
        provider: csi

      features: EnableCSI

    backupsEnabled: true
    snapshotsEnabled: true
    deployRestic: true

    restic:
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          memory: 256Mi
