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
- out of the box support for volume snapshots
- optional NVIDIA GPU agent pools (driver + toolkit, containerd `nvidia` runtime,
  `RuntimeClass`)
- RuntimeClasses for the container runtimes an agent pool's image carries

### Versioning

| Component                  | Version                                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| OpenStack                  | 2024.1 Caracal (verified), maybe older version are supported too                                                         |
| RKE2                       | [v1.37.1+rke2r1](https://github.com/rancher/rke2/releases/tag/v1.37.1+rke2r1), the only minor supported                |
| OpenStack Cloud Controller | [v2.37.1](https://github.com/kubernetes/cloud-provider-openstack/releases/tag/openstack-cloud-controller-manager-2.37.1) |
| OpenStack Cinder           | [v2.37.1](https://github.com/kubernetes/cloud-provider-openstack/releases/tag/openstack-cinder-csi-2.37.1)               |
| Kube-vip                   | [v1.3.0](https://github.com/kube-vip/kube-vip/releases/tag/v1.3.0)                                                       |

### Bundled RKE2 components

Servers deploy none of RKE2's ingress controllers, Gateway API CRDs or
telemetry: install your own. RuntimeClasses come from the pools
(`runtime_classes`, `gpu.runtime_class`). Every node runs UFW with the
security groups' rules (`rules_*`): a port your workloads open on the nodes
needs one. Node ports answer on the agents only. CoreDNS and metrics-server run on
the agents too, one per untainted agent node and two at most: a cluster has at
least one agent without taints.

### Secrets

`user_data` holds no cluster secret: keep secrets out of `manifests`,
`manifests_folder` and `rke2_config`, which it carries. tofu pushes the rest
over SSH through the floating IP, so `rules_ssh_cidr` includes where tofu runs;
a change to what it pushes replaces the nodes. The `ssh_cmd` and `ssh_config`
outputs check the host keys tofu makes (OpenSSH 8.5 or later).

### Bootstrap

With several servers, the first apply has `bootstrap = true`: the first server
starts the cluster alone. Once that apply is through, set `bootstrap = false`
and apply again: tofu pushes that server the `server:` line it joins through,
should it ever restart on an empty database. Nothing is replaced.

The floating IP is on the VIP from the start. The first server holds the VIP
itself while it starts the cluster alone (`bootstrap = true`, or a single
server, as its instance metadata says), until rke2 starts kube-vip: tofu
reaches it through the floating IP to push the secrets rke2 waits for. A first
server replaced later joins, and leaves the VIP to kube-vip.

A single server takes no `bootstrap`: it always starts the cluster alone, and
keeps its rke2 volume across rebuilds. To add servers to it:

1. Add them with `bootstrap = true` and `ff_grow_from_single_server = true`:
   the first server is rebuilt on its own volume, its manifests counting the
   operators' replicas anew, and the others join it.
2. Set `bootstrap = false`, as for any new cluster.
3. Drop `ff_grow_from_single_server` and replace the first server, one node at
   a time as any replacement: it comes back on a blank volume and joins the
   others. Kept, its old database would bring back an etcd member they removed
   when its Node went.

The other way round, from several servers to one, is a new cluster.

### Options

| Option | Effect |
| ------ | ------ |
| `ff_gateway_api_crd` | RKE2 installs the Gateway API CRDs again |
| `ff_grow_from_single_server` | While a single server becomes several, the first keeps its rke2 volume (Bootstrap above) |
| `security_groups` | `false`: no security group nor port security, for clouds that refuse security groups: UFW alone filters traffic to the nodes |
| `ssh_authorized_keys` | The first is the instances' keypair, tofu pushes the others over SSH: changing them replaces no node; each is one public key and its comment, without options |
| `kubelet_config` | Replaces the KubeletConfiguration that turns graceful node shutdown on (RKE2 leaves it off) |
| `storage_classes` | The Cinder StorageClasses; defaults to `csi-cinder-retain` (default) and `csi-cinder-delete` |
| `image_prebuilt` | The pool's image already carries the packages: cloud-init skips them |
| `cilium_values` | rke2-cilium values the module leaves to the chart, by top-level key (`encryption`, `hubble`...): repeating one of the module's fails the plan |

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

# get the SSH helpers, which check the nodes' host keys (restore_cmd carries the
# restore key: read it only to restore)
terraform output -raw ssh_config

# on upgrade, process node pool by node pool
terraform apply -target='module.rke2.module.servers["server-a"]'
```

See [examples](./examples) for more options or this
[article](https://zifeo.com/articles/230617-low-cost-k8s) for a step-by-step
tutorial.

Note: it requires [yq](https://github.com/mikefarah/yq) to generate remote kubeconfig file. You
can disable this behavior by setting `ff_write_kubeconfig=false` and fetch
yourself `/etc/rancher/rke2/rke2.yaml` on server nodes.

## Restoring a backup

The `restore_cmd` output carries the restore key: start the line with a space,
which Ubuntu's bash keeps out of its history. The floating IP leads to the
server holding the VIP, which none does while rke2 is down everywhere: first
attach another floating IP to the port of the server that restores, by hand
(OpenStack console or `openstack floating ip set --port`), work through it, and
detach it at the end. A cluster that is down is no time for an apply. As in
[RKE2's guide](https://docs.rke2.io/datastore/backup_restore):

```
# on every server (the ssh_config output reaches each node by its instance
# name: replace its floating IP with the rescue one)
sudo systemctl stop rke2-server
# on the one that restores: rke2 refuses to reset a member that joins another
# (the first server's server: line is in 40-join.yaml once bootstrap is false)
sudo sed -i '/^server:/d' /etc/rancher/rke2/config.yaml
sudo rm -f /etc/rancher/rke2/config.yaml.d/40-join.yaml
# the restore_cmd output, with the snapshot's name in the bucket
sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=BUCKET --etcd-s3-access-key=RESTORE_KEY --etcd-s3-secret-key=RESTORE_SECRET --cluster-reset-restore-path=SNAPSHOT_NAME
sudo systemctl start rke2-server
# on the other servers, which then join it through the internal VIP: the first
# server, made without server:, would otherwise start a cluster of its own
# (INTERNAL_VIP: subnet_servers_vip, by default .4 of subnet_servers_cidr)
grep -q '^server:' /etc/rancher/rke2/config.yaml || echo 'server: "https://INTERNAL_VIP:9345"' | sudo tee -a /etc/rancher/rke2/config.yaml
sudo rm -rf /var/lib/rancher/rke2/server/db
sudo systemctl start rke2-server
# back on the one that restored, once the others joined: the same line, so that
# it too rejoins through the VIP should its db ever go
grep -q '^server:' /etc/rancher/rke2/config.yaml || echo 'server: "https://INTERNAL_VIP:9345"' | sudo tee -a /etc/rancher/rke2/config.yaml
# then every node, one at a time, once all are Ready: watches opened before the
# restore miss what it rolled back (kube-vip keeps servers out of the VIP)
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

When any agent pool has `gpu.enabled = true`, node DaemonSets that must run on
every agent (Cinder CSI nodePlugin) automatically gain an `nvidia.com/gpu`
toleration (and any agent `node_taints`) so volumes work on GPU nodes. Override
with `agent_daemonset_tolerations` if needed.

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
    image_name  = "Ubuntu 26.04 LTS Resolute Raccoon"
    system_user = "ubuntu"

    boot_volume_size = 40
    rke2_version     = "v1.37.1+rke2r1"
    rke2_volume_size = 64

    # Optional: keep GPU workloads off other pools
    # node_taints = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
    # node_labels = { "nvidia.com/gpu.present" = "true" }

    gpu = {
      enabled = true
      # defaults:
      # driver = { package = "nvidia-driver-580", version = null, preinstalled = false }
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
| `driver.package` | `nvidia-driver-580` | Apt package for the NVIDIA kernel driver (580 production branch on Ubuntu 24.04 and 26.04; `nvidia-driver-550` is now a transitional package to it) |
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
4. Removes any RKE2 containerd template (`config.toml.tmpl`,
   `config-v3.toml.tmpl`): RKE2 registers the `nvidia` runtime once it is on
   its PATH, and a template adding it again makes containerd fail.
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

## Development

The tools are pinned with their checksums in `mise.toml` and `mise.lock`;
Docker runs the shellcheck and chart patch tests in a node-like image.

```bash
mise install --locked
uv run pytest                        # static and chart patch tests
(cd tests/cloud-init && tofu test)   # cloud-init rendering
```

## Migration guide

### From v5 to v6

Every node is replaced, one at a time, servers first. You need OpenTofu 1.10 or later, OpenSSH 8.5 or later, jq, and
kubectl with the kubeconfig v5 wrote. Below, `module.rke2` is the module in your root, CLUSTER its `name`, NAME a
`servers` or `agents` entry, NODE one of its Kubernetes nodes (`CLUSTER-NAME-<n>`) and N that node's number minus
one.

1. Run RKE2 v1.36 with the last v5 release: v6 supports v1.37 only, and RKE2 upgrades one minor at a time.
2. Install your own ingress controller and Gateway API CRDs (or set `ff_gateway_api_crd = true`). A GPU pool whose
   pods ask for the `nvidia` RuntimeClass sets `gpu.runtime_class = true`. v6 nodes run UFW with the security
   groups' rules: a port your workloads open on the nodes (a `hostPort`, a host-network exporter) goes in
   `rules_*_*`.
3. Rename the inputs:

   | v5 | v6 |
   | --- | --- |
   | `bootstrap` with several servers | `bootstrap = false`, now required |
   | `bootstrap = true` with one server | none: a single server always starts the cluster alone |
   | `rules_ssh_cidr = null` | the CIDRs to reach the servers by SSH, including where tofu runs |
   | `ff_autoremove_agent` | `agent_removal_timeout` |
   | `ff_native_backup` | `etcd_snapshots_in_object_store` |
   | `ff_with_kubeproxy` | `kube_proxy` |
   | `ff_infomaniak_sc = true` | `storage_classes`, one per volume type (`parameters.type`) |
   | `s3_backup` with empty strings | `s3_backup = null` |
   | `s3_backup` | `s3_backup` with `retention`, `restore_access_key` and `restore_access_secret` |
   | `enable_cilium_encryption`, `enable_cilium_node_encryption` | `cilium_values.encryption` |
   | `servers_firewall`, `cni` | none |

   Keep `security_groups` true. `etcd_snapshots_in_object_store = false` destroys the `CLUSTER-etcd-snapshots`
   container v5 made, with what it holds. The Infomaniak classes drop the `sc-` prefix. Hubble is off, as in RKE2:

   ```hcl
   cilium_values = {
     encryption = { enabled = true, type = "wireguard", nodeEncryption = true }
     hubble     = { enabled = true, relay = { enabled = true }, metrics = { enabled = ["dns", "drop", "flow"] } }
   }
   ```
4. Point the pools at Ubuntu 26.04 images and RKE2 v1.37, the module at v6, then run `tofu init -upgrade`.
5. Before any plan, move the servers' token to a `random_password`, keeping its value. Add this to your root for this
   step only:

   ```hcl
   variable "rke2_token_v5" {
     type = string
   }

   import {
     to = module.rke2.random_password.rke2_token
     id = var.rke2_token_v5
   }
   ```

   ```sh
   export TF_VAR_rke2_token_v5=$(tofu state pull | jq -er '.resources[] | select(.module == "module.rke2" and .type == "random_string" and .name == "rke2_token") | .instances[0].attributes.result')
   # the import prints the token
   tofu apply -concise -auto-approve -target=module.rke2.random_password.rke2_token >/dev/null
   tofu state rm module.rke2.random_string.rke2_token
   unset TF_VAR_rke2_token_v5
   ```

   Then remove both blocks: `tofu plan -concise -target=module.rke2.random_password.rke2_token` shows no change.
6. Two state changes no plan makes:

   ```sh
   # v5's drain hooks, which v6 cannot destroy: step 10 drains by hand
   tofu state list | grep 'null_resource.agent_remove'
   tofu state rm 'ADDRESS'   # each address listed
   # each 51871/udp rule of yours in rules_*_* becomes the module's: server_server to server->server, and so on
   tofu state mv 'module.rke2.openstack_networking_secgroup_rule_v2.server_server["udp-51871"]' 'module.rke2.openstack_networking_secgroup_rule_v2.default["server->server-udp-51871"]'
   ```

   Then drop those rules from `rules_*_*`.
7. Apply everything but the nodes. It replaces nothing:

   ```sh
   tofu apply -concise -exclude=module.rke2.module.servers -exclude=module.rke2.module.agents
   ```
8. Prepare the v5 nodes:

   ```sh
   kubectl create namespace rke2-v6
   # on each node: the file v6's Cinder node plugin reads
   kubectl -n rke2-v6 debug node/NODE -q --profile=general --attach --image=busybox:1.37 -- \
     sh -c 'mkdir -p /host/etc/config && printf "[BlockStorage]\nignore-volume-az = true\nrescan-on-resize = true\n[Metadata]\nsearch-order = configDrive\n" > /host/etc/config/cloud.conf'
   # with several servers, on each server: its host key, which tofu meets through the floating IP until the last v5
   # server is replaced
   kubectl -n rke2-v6 debug node/NODE -q --profile=general --attach --image=busybox:1.37 -- cat /host/etc/ssh/ssh_host_ed25519_key.pub
   kubectl delete namespace rke2-v6
   ```

   Add each server's key, as `FLOATING_IP KEY`, to the global known hosts file `ssh -G FLOATING_IP` names
   (`globalknownhostsfile`), and remove those lines once step 9 is through.
9. Replace the servers, the first one first:

   ```sh
   kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
   tofu apply -concise -destroy -target='module.rke2.module.servers["NAME"].openstack_compute_instance_v2.instance[0]'
   kubectl delete node NODE
   tofu apply -concise -target='module.rke2.module.servers["NAME"]' -target=module.rke2.terraform_data.cluster_secrets
   ```

   Then each other server the same way, without `-target=module.rke2.terraform_data.cluster_secrets`. A single
   server skips the drain and the node deletion: the cluster stops meanwhile and comes back on its rke2 volume.
10. Replace the agents the same way, one at a time. A v5 agent whose rke2 restarts meanwhile cannot rejoin: replace
    it next.

    ```sh
    kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
    tofu apply -concise -destroy -target='module.rke2.module.agents["NAME"].openstack_compute_instance_v2.instance[N]'
    kubectl delete node NODE
    tofu apply -concise -target='module.rke2.module.agents["NAME"].terraform_data.secrets[N]' -target='module.rke2.module.agents["NAME"].null_resource.wait_for_rke2[N]'
    ```
11. Clean up what the module no longer manages:
    - the `restic` container, if it holds nothing you need; the `velero` container stays;
    - Velero: `kubectl -n kube-system delete helmchart velero`, then the `velero` namespace, then install it on your
      own;
    - the `sc-ceph-*` AddOns in `kube-system`;
    - on a GPU cluster, if `kubectl get runtimeclass nvidia` finds none, `sudo systemctl restart rke2-server` on a
      server.
12. Run `tofu apply -concise`: it replaces no instance.
13. Recommended: rotate the application credential, the snapshots' key and the servers' token.
    1. The credentials, with the first server, then each other server right away as in step 9. Without
       `etcd_snapshots_in_object_store`, drop the second `-replace` and put a new key in `s3_backup`:

       ```sh
       kubectl drain NODE --ignore-daemonsets --delete-emptydir-data
       tofu apply -concise -destroy -target='module.rke2.module.servers["NAME"].openstack_compute_instance_v2.instance[0]'
       kubectl delete node NODE
       tofu apply -concise -replace=module.rke2.openstack_identity_application_credential_v3.rke2 -replace='module.rke2.openstack_identity_ec2_credential_v3.s3[0]' -target='module.rke2.module.servers["NAME"]' -target=module.rke2.terraform_data.cluster_secrets
       ```
    2. The token, on the server the floating IP leads to. No other server may restart until it is replaced:

       ```sh
       tofu apply -concise -replace=module.rke2.random_password.rke2_token -target=module.rke2.random_password.rke2_token
       tofu output -raw ssh_config > ssh_config
       tofu state pull | jq -er '.resources[] | select(.module == "module.rke2" and .type == "random_password" and .name == "rke2_token") | .instances[0].attributes.result' | ssh -F ssh_config CLUSTER 'read -r new && sudo rke2 token rotate --new-token "$new"'
       ssh -F ssh_config CLUSTER
       # on that server
       sudo sh -c 'printf "token: \"%s\"\n" "$(cat /var/lib/rancher/rke2/server/token)" > /etc/rancher/rke2/config.yaml.d/49-token.yaml'
       sudo systemctl restart rke2-server
       ```

       Then replace every server as in step 9, the one holding the VIP last
       (`kubectl -n kube-system get lease plndr-cp-lock -o jsonpath='{.spec.holderIdentity}'`).
    3. Run `sudo rke2 etcd-snapshot save` on a server: older snapshots restore only with the old token.

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
      image: ghcr.io/kube-vip/kube-vip:v1.2.4
      imagePullPolicy: IfNotPresent
      args:
        - manager
      env:
        - name: vip_arp
          value: "true"
        - name: port
          value: "6443"
        - name: vip_subnet
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
