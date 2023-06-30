# Terraform RKE2 OpenStack

[![Terraform Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/zifeo/rke2/openstack/latest)

Easily deploy a high-availability RKE2 Kubernetes cluster on OpenStack providers
(e.g. [Infomaniak](https://www.infomaniak.com/fr/hebergement/public-cloud),
[OVH](https://www.ovhcloud.com/fr/public-cloud/), etc.). This project aims at
offering a simple and stable distribution rather than supporting all
configuration possibilities.

Inspired and reworked from
[remche/terraform-openstack-rke2](https://github.com/remche/terraform-openstack-rke2)
to add an easier interface, high-availability, load-balancing and sensible
defaults for running production workload.

## Features

- [RKE2](https://docs.rke2.io) Kubernetes distribution : lightweight, stable,
  simple and secure
- persisted `/var/lib/rancher/rke2` for single server durability
- configure Openstack Swift or S3-like backend for automated etcd snapshots
- smooth updates & agent nodes autoremoval with pod draining
- bundled with Openstack Cloud Controller and Cinder CSI
- Cilium networking (network policy support and no kube-proxy)
- highly-available through load balancers
- out of the box support for volume snapshot and Velero

### Versioning

| Component                  | Version                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| OpenStack                  | 2023.1 Antelope (verified), maybe older version are supported too                                                        |
| RKE2                       | [v1.26.6+rke2r1](https://github.com/rancher/rke2/releases/tag/v1.26.6%2Brke2r1)                                          |
| OpenStack Cloud Controller | [v1.27.1](https://github.com/kubernetes/cloud-provider-openstack/tree/v1.27.1/charts/openstack-cloud-controller-manager) |
| OpenStack Cinder           | [v1.27.1](https://github.com/kubernetes/cloud-provider-openstack/tree/v1.27.1/charts/cinder-csi-plugin)                  |
| Velero                     | [v2.32.6](https://github.com/vmware-tanzu/helm-charts/tree/velero-2.32.6/charts/velero)                                  |

## Getting started

```bash
git clone git@github.com:zifeo/terraform-openstack-rke2.git && cd terraform-openstack-rke2/examples/single-server
cat <<EOF > terraform.tfvars
project=PCP-XXXXXXXX
username=PCU-XXXXXXXX
password=XXXXXXXX
EOF

terraform init
terraform apply # approx 2-3 mins
kubectl --kubeconfig single-server.rke2.yaml get nodes
# NAME           STATUS   ROLES                       AGE     VERSION
# k8s-pool-a-1   Ready    <none>                      119s    v1.21.5+rke2r2
# k8s-server-1   Ready    control-plane,etcd,master   2m22s   v1.21.5+rke2r2

# on upgrade, process node pool by node pool
terraform apply -target='module.rke2.module.servers["server-a"]'
# for servers, apply on the majority of nodes, then for the remaining ones
# this ensures the load balancer routes are updated as well
terraform apply -target='module.rke2.openstack_lb_members_v2.k8s'
```

See [examples](./examples) for more options or this
[article](https://zifeo.com/articles/230617-low-cost-k8s) for a step-by-step
tutorial.

Note: it requires [rsync](https://rsync.samba.org) and
[yq](https://github.com/mikefarah/yq) to generate remote kubeconfig file. You
can disable this behavior by setting `ff_write_kubeconfig=false` and fetch
yourself `/etc/rancher/rke2/rke2.yaml` on server nodes.

## Infomaniak OpenStack

A stable, performant and fully equipped Kubernetes cluster in Switzerland for as
little as CHF 26.90/month (at the time of writing):

- load-balancer with floating IP (perfect under Cloudflare proxy)
- 1 server 2cpu/4Go (= master)
- 1 agent 2cpu/4Go (= worker)

| Flavour                                                                            | CHF/month |
| ---------------------------------------------------------------------------------- | --------- |
| 2×5.88 (instances) + 0.09×2×(4+6) (block storage) + 3.34 (IP) + 10 (load-balancer) | 26.90     |
| single 2cpu/4go server with 1x4cpu/16Go worker                                     | ~37.—     |
| 3x2cpu/4go HA servers with 1x4cpu/16Go worker                                      | ~50.—     |
| 3x2cpu/4go HA servers with 3x4cpu/16Go workers                                     | ~85.—     |

See their technical [documentation](https://docs.infomaniak.cloud) and
[pricing](https://www.infomaniak.com/fr/hebergement/public-cloud/tarifs).

## More on RKE2 & OpenStack

[RKE2 cheat sheet](https://gist.github.com/superseb/3b78f47989e0dbc1295486c186e944bf)

```
# alias already set on the nodes
crictl
kubectl (server only)

# logs
sudo systemctl status rke2-server
journalctl -f -u rke2-server
sudo systemctl status rke2-agent.service
journalctl -f -u rke2-agent
less /var/lib/rancher/rke2/agent/logs/kubelet.log
less /var/lib/rancher/rke2/agent/containerd/containerd.log
less /var/log/cloud-init-output.log

# restore s3 snapshot (see restore_cmd output of the terraform module)
sudo systemctl stop rke2-server && sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=BUCKET_NAME --etcd-s3-access-key=ACCESS_KEY --etcd-s3-secret-key=SECRET_KEY --cluster-reset-restore-path=SNAPSHOT_PATH && sudo reboot
# remove db on other server nodes
sudo systemctl stop rke2-server && sudo rm -rf /var/lib/rancher/rke2/server/db && sudo reboot
# reboot all nodes

# check san
openssl s_client -connect 192.168.42.3:10250 </dev/null 2>/dev/null | openssl x509 -inform pem -text

# defrag etcd
kubectl -n kube-system exec $(kubectl -n kube-system get pod -l component=etcd --no-headers -o custom-columns=NAME:.metadata.name | head -1) -- sh -c "ETCDCTL_ENDPOINTS='https://127.0.0.1:2379' ETCDCTL_CACERT='/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt' ETCDCTL_CERT='/var/lib/rancher/rke2/server/tls/etcd/server-client.crt' ETCDCTL_KEY='/var/lib/rancher/rke2/server/tls/etcd/server-client.key' ETCDCTL_API=3 etcdctl defrag --cluster"

# increase volume size
# shutdown instance
# detach volumne
# expand volume
# recreate node
terraform apply -target='module.rke2.module.servers["server"]' -replace='module.rke2.module.servers["server"].openstack_compute_instance_v2.instance[0]'
```
