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
- persisted `/var/lib/rancher/rke2` when there is a single server
- automated etcd snapshots with Openstack Swift support or other S3-like backend
- smooth updates & agent nodes autoremoval with pod draining
- integrated Openstack Cloud Controller (load-balancer, etc.) and Cinder CSI
- Cilium networking (network policy support and no kube-proxy)
- highly-available via kube-vip and dynamic peering (no load-balancer required)
- out of the box support for volume snapshot and Velero
- optional NVIDIA GPU agent pools (driver + toolkit, containerd `nvidia` runtime,
  `RuntimeClass`)

### Versioning

| Component                  | Version                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| OpenStack                  | 2024.1 Caracal (verified), maybe older version are supported too                                                         |
| RKE2                       | [v1.35.4+rke2r1](https://github.com/rancher/rke2/releases/tag/v1.35.4+rke2r1)                                            |
| OpenStack Cloud Controller | [v2.34.1](https://github.com/kubernetes/cloud-provider-openstack/releases/tag/openstack-cloud-controller-manager-2.34.1) |
| OpenStack Cinder           | [v2.34.1](https://github.com/kubernetes/cloud-provider-openstack/releases/tag/openstack-cinder-csi-2.34.1)               |
| Velero                     | [v11.3.2](https://github.com/vmware-tanzu/helm-charts/releases/tag/velero-11.3.2)                                        |
| Kube-vip                   | [v0.7.2](https://github.com/kube-vip/kube-vip/releases/tag/v0.7.2)                                                       |

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

# get SSH and restore helpers
terraform output -json

# on upgrade, process node pool by node pool
terraform apply -target='module.rke2.module.servers["server-a"]'
```

See [examples](./examples) for more options or this
[article](https://zifeo.com/articles/230617-low-cost-k8s) for a step-by-step
tutorial.

Note: it requires [rsync](https://rsync.samba.org) and
[yq](https://github.com/mikefarah/yq) to generate remote kubeconfig file. You
can disable this behavior by setting `ff_write_kubeconfig=false` and fetch
yourself `/etc/rancher/rke2/rke2.yaml` on server nodes.

## Restoring a backup

```
# remove server url from rke2 config
sudo vim /etc/rancher/rke2/config.yaml
# ssh into one of the server nodes (see terraform output -json)
# restore s3 snapshot (see restore_cmd output of the terraform module):
sudo systemctl stop rke2-server
sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=BUCKET_NAME --etcd-s3-access-key=ACCESS_KEY --etcd-s3-secret-key=SECRET_KEY --cluster-reset-restore-path=SNAPSHOT_PATH
sudo systemctl start rke2-server
# exit and ssh on the other server nodes to remove the etcd db
# (recall that you may need to ssh into one node as a bastion then to the others):
sudo systemctl stop rke2-server
sudo rm -rf /var/lib/rancher/rke2/server
sudo systemctl start rke2-server
# reboot all nodes one by one to make sure all is stable
sudo reboot
```

## Infomaniak OpenStack

A stable, performant and fully equipped Kubernetes cluster in Switzerland for as
little as CHF 18.—/month (at the time of writing):

- 1 server 2cpu/4Go (= master)
- 1 agent 1cpu/2Go (= worker)
- 1 floating IP for admin access (ssh and kubernetes api)
- 1 floating IP for private network gateway

| Flavour                                                              | CHF/month |
| -------------------------------------------------------------------- | --------- |
| 5.88 + 2.93 (instances) + 0.09×2×(6+8) (block storage) + 2×3.34 (IP) | 18.—      |
| 1x2cpu/4go server with 1x4cpu/16Go worker                            | ~28.—     |
| 3x2cpu/4go HA servers with 1x4cpu/16Go worker                        | ~41.—     |
| 3x2cpu/4go HA servers with 3x4cpu/16Go workers                       | ~76.—     |

You may also want to add a load-balancer and bind an additional floating IP for
public access (e.g. for an ingress controller like ingress-nginx), that will add
10.00 (load-balancer) + 3.34 (IP) = CHF 13.34/month. Note that physical
load-balancer can be shared by many Kubernetes load-balancers when there is no
port collision.

See their technical [documentation](https://docs.infomaniak.cloud) and
[pricing](https://www.infomaniak.com/fr/hebergement/public-cloud/tarifs).

## GPU nodes

Agent pools can opt into NVIDIA GPU support. The module answers one question per
pool — **does this node have a GPU?** When enabled, it installs the runtime
stack on the node so containers can use the GPU via RKE2’s containerd.

This does **not** deploy the [NVIDIA GPU Operator](https://docs.rke2.io/add-ons/gpu_operators)
(device plugin, DCGM, NRI/CDI). Without the operator, `nvidia.com/gpu` is not an
allocatable resource; workloads must set `runtimeClassName: nvidia` and
scheduling isolation is left to your existing `node_taints` / `node_labels`.

### Define a GPU agent pool

```hcl
agents = [
  {
    name        = "example-gpu"
    nodes_count = 1

    # Infomaniak: GPU flavors are often project-gated (e.g. nvl4-* for L4).
    # Enable them with support before terraform apply.
    flavor_name = "nvl4-a8-ram16-disk50-perf1"
    # Infomaniak does not ship a GPU-ready image — use a standard Ubuntu image.
    image_name  = "Ubuntu 24.04 LTS Noble Numbat"
    system_user = "ubuntu"

    boot_volume_size = 40
    rke2_version     = "v1.35.6+rke2r1"
    rke2_volume_size = 64

    # Optional: keep GPU workloads off other pools
    # node_taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
    # node_labels = { "nvidia.com/gpu.present" = "true" }

    gpu = {
      enabled = true
      # defaults:
      # driver = { package = "nvidia-driver-550", version = null, preinstalled = false }
      # toolkit_package = "nvidia-container-toolkit"
      # toolkit_version = null  # set to pin, e.g. "1.17.8-1"
      # runtime_class   = true  # deploys a cluster RuntimeClass named "nvidia"
    }
  }
]
```

| Option | Default | Meaning |
| ------ | ------- | ------- |
| `enabled` | `false` | Turn on GPU cloud-init on this pool |
| `driver.package` | `nvidia-driver-550` | Apt package for the NVIDIA kernel driver (Ubuntu 24.04 + L4) |
| `driver.version` | `null` | Optional apt version pin for `driver.package` |
| `driver.preinstalled` | `false` | Skip driver install if the image already has it |
| `toolkit_package` | `nvidia-container-toolkit` | Provides `nvidia-container-runtime` |
| `toolkit_version` | `null` | Optional apt version pin for `toolkit_package` |
| `runtime_class` | `true` | Ship a cluster `RuntimeClass` (`handler: nvidia`) when any pool requests it |

Control-plane (`servers`) pools do not get GPU setup in this version.

### What the module does on the node

1. Adds the NVIDIA container-toolkit apt repository (when GPU is enabled).
2. Installs the driver and toolkit packages (unless `preinstalled = true`).
3. Always reboots once after a fresh driver install so the kernel module loads
   (drivers are kernel-sensitive).
4. Writes RKE2 containerd templates (`config.toml.tmpl` /
   `config-v3.toml.tmpl`) registering the `nvidia` runtime
   (`{{ template "base" . }}` — do not hand-edit generated `config.toml`).
5. Puts the toolkit on the `rke2-agent` PATH via `/etc/default/rke2-agent`.
6. Starts `rke2-agent` only after GPU setup succeeds.

If you use `ff_wait_ready = true`, expect a longer first boot on GPU nodes
because of the driver reboot; Terraform’s wait can time out during that window.

### Verify on a GPU node

```bash
lsmod | grep nvidia
cat /proc/driver/nvidia/version
command -v nvidia-container-runtime
grep -A5 nvidia /var/lib/rancher/rke2/agent/etc/containerd/config.toml
kubectl get runtimeclass nvidia
```

Example pod (V1 — runtime class only; GPU resource limits need the operator):

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nvidia-smi
spec:
  runtimeClassName: nvidia
  restartPolicy: Never
  containers:
    - name: cuda
      image: nvidia/cuda:12.4.1-base-ubuntu22.04
      command: ["nvidia-smi"]
```

### Later: GPU Operator (V2)

With the NVIDIA GPU Operator (NRI/CDI on recent RKE2/containerd), the manual
containerd template and `RuntimeClass` become unnecessary and
`nvidia.com/gpu` becomes allocatable. That path is intentionally out of scope
for this module version.

## More on RKE2 & OpenStack

[RKE2 cheat sheet](https://gist.github.com/superseb/3b78f47989e0dbc1295486c186e944bf)

```
# alias already set on the nodes
crictl
kubectl (server only)

# logs
sudo systemctl status rke2-server.service
journalctl -f -u rke2-server

sudo systemctl status rke2-agent.service
journalctl -f -u rke2-agent

less /var/lib/rancher/rke2/agent/logs/kubelet.log
less /var/lib/rancher/rke2/agent/containerd/containerd.log
less /var/log/cloud-init-output.log

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

## Migration guide

### From v2 to v3

```
# 1. use the previous patch version (2.0.7) to setup an additional san for 192.168.42.4
# this will become the new VIP inside the cluster and replace the load-balancer:
source  = "zifeo/rke2/openstack"
version = "2.0.7"
# ...
additional_san = ["192.168.42.4"]
# 2. run an full upgrade with it, node by node:
terraform apply -target='module.rke2.module.servers["your-server-pool"]'
# 3. you can now switch to the new major and remove the additional_san:
source  = "zifeo/rke2/openstack"
version = "3.0.0"
# 4. create the new external IP for admin access (that will be different from the load-balancer) with:
terraform apply -target='module.rke2.openstack_networking_floatingip_associate_v2.fip'
# 5. pick a server different from the initial one (used to bootstrap):
terraform apply -target='module.rke2.module.servers["server-c"].openstack_networking_port_v2.port'
# 6. give to that server the control of the VIP
ssh ubuntu@server-c
sudo su
modprobe ip_vs
modprobe ip_vs_rr
cat <<EOF > /var/lib/rancher/rke2/agent/pod-manifests/kube-vip.yaml
apiVersion: v1
kind: Pod
metadata:
  name: kube-vip
  namespace: kube-system
spec:
  containers:
    - name: kube-vip
      image: ghcr.io/kube-vip/kube-vip:v0.7.2
      imagePullPolicy: IfNotPresent
      args:
        - manager
      env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_cidr
          value: "32"
        - name: cp_enable
          value: "true"
        - name: cp_namespace
          value: kube-system
        - name: vip_ddns
          value: "false"
        - name: svc_enable
          value: "false"
        - name: vip_leaderelection
          value: "true"
        - name: vip_leasename
          value: plndr-cp-lock
        - name: vip_leaseduration
          value: "15"
        - name: vip_renewdeadline
          value: "10"
        - name: vip_retryperiod
          value: "2"
        - name: enable_node_labeling
          value: "true"
        - name: lb_enable
          value: "true"
        - name: lb_port
          value: "6443"
        - name: lb_fwdmethod
          value: local
        - name: address
          value: 192.168.42.4
        - name: prometheus_server
          value: ":2112"
      resources:
        requests:
          cpu: 100m
          memory: 64Mi
        limits:
          memory: 64Mi
      securityContext:
        capabilities:
          add:
            - NET_ADMIN
            - NET_RAW
      volumeMounts:
        - mountPath: /etc/kubernetes/admin.conf
          name: kubeconfig
  restartPolicy: Always
  hostAliases:
    - hostnames:
        - kubernetes
      ip: 127.0.0.1
  hostNetwork: true
  volumes:
    - name: kubeconfig
      hostPath:
        path: /etc/rancher/rke2/rke2.yaml
EOF
# 7. you should see a pod in kube-system starting with kube-vip (investigate if failling)
# then apply the migration to the initial/bootstraping server:
terraform apply -target='module.rke2.module.servers["server-a"]'
terraform apply -target='module.rke2.openstack_networking_secgroup_rule_v2.outside_servers'
# 8. the cluster IP has now changed, and you should update your kubeconfig with the new ip (look in horizon)
# 9. import the load-balancer and its ip elsewhere if used (otherwise they will be destroyed)
cat <<EOF > lb.tf
resource "openstack_lb_loadbalancer_v2" "lb" {
  name                  = "lb"
  vip_network_id        = module.rke2.network_id
  vip_subnet_id         = module.rke2.lb_subnet_id
  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
resource "openstack_networking_floatingip_v2" "external" {
  pool    = "ext-floating1"
  port_id = openstack_lb_loadbalancer_v2.lb.vip_port_id
}
EOF
terraform state show module.rke2.openstack_lb_loadbalancer_v2.lb
terraform import openstack_lb_loadbalancer_v2.lb ID
terraform state rm module.rke2.openstack_lb_loadbalancer_v2.lb
terraform state show module.rke2.openstack_networking_floatingip_v2.external
terraform import openstack_networking_floatingip_v2.external ID
terraform state rm module.rke2.openstack_networking_floatingip_v2.external
# 10. continues by upgrading other nodes step-by-step as you would do it normally:
terraform apply -target='module.rke2.module.POOL["NODE"]'
# 11. once all the nodes are upgraded, make sure that everything is well applied:
terraform apply
```
