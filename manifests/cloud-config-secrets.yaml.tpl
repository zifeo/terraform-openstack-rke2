# OCCM's credentials as a Secret, which etcd and its snapshots keep encrypted, not in the HelmChart's values, which they
# keep as written, nor in the servers' user_data, which Nova keeps and serves: tofu applies it through the API
# (../hooks.tf). Not the name the chart created before (cloud-config): the upgrade that stops it creating that Secret has
# Helm delete it.
# OCCM's values quoted, as its chart wrote them
apiVersion: v1
kind: Secret
metadata:
  name: rke2-occm-cloud-config
  namespace: kube-system
type: Opaque
stringData:
  cloud.conf: |
    [Global]
    application-credential-id = "${app_id}"
    application-credential-name = "${app_name}"
    application-credential-secret = "${app_secret}"
    auth-url = "${auth_url}"
    region = "${region}"
    tenant-id = "${project_id}"

    [LoadBalancer]
    %{~ if floating_network_id != null ~}
    floating-network-id = "${floating_network_id}"
    %{~ endif ~}
    lb-provider = "${lb_provider}"
    manage-security-groups = "${manage_sg}"
    max-shared-lb = "10"
    member-subnet-id = "${subnet_id}"
    network-id = "${network_id}"
    subnet-id = "${subnet_id}"
