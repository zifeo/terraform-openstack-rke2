# Terraform RKE2 OpenStack

[![Terraform Registry](https://img.shields.io/badge/terraform-registry-blue.svg)](https://registry.terraform.io/modules/zifeo/rke2/openstack/latest)

Easily deploy a high-availability RKE2 Kubernetes cluster on OpenStack providers
(e.g. [Infomaniak](https://www.infomaniak.com/fr/hebergement/public-cloud),
[OVH](https://www.ovhcloud.com/fr/public-cloud/), etc.). This project aims at
offering a simple and stable distribution rather than supporting all
configuration possibilities.

Inspired and reworked from
[remche/terraform-openstack-rke2](https://github.com/remche/terraform-openstack-rke2)
to add an easier interface, high-availability, stricter security groups,
persistent storage, load-balancer integration and S3 automated etcd snapshots.

## Features

- [RKE2](https://docs.rke2.io) Kubernetes distribution : lightweight, stable,
  simple and secure
- persisted `/var/lib/rancher/rke2` for (single) server durability
- configure Openstack Swift or S3-like backend for automated etcd snapshots
- smooth updates & agent nodes autoremoval with draining
- bundled with Openstack Cinder CSI
- Cilium networking (network policy support and no Kube-proxy)
- load balancers (Openstack Octivia) provisioning
- highly-available through ip failovers (via address-pairs and VRRP)
- out of the box support for volume snapshot and Velero

<img src="https://github.com/zifeo/terraform-openstack-rke2/raw/main/example/net.png" height="400" />

### Next features

- [Magnum autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler/cloudprovider/magnum)
- single-ip output NAT
- gpu bindings

## Getting started

```bash
cat <<EOF > cluster.tf
provider "openstack" {
  tenant_name = "PCP-XXXXXXX"
  user_name   = "PCU-XXXXXXX"
  password    = "XXXXXXXXXXX"
  auth_url    = "https://api.pub1.infomaniak.cloud/identity"
  region      = "dc3-a"
}

module "rke2" {
  source  = "zifeo/rke2/openstack"

  name = "k8s"

  floating_pool = "ext-floating1"
  rules_ext = [
    { "port" : 22, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 80, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 6443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
  ]

  servers = [
    {
      name = "server-a"

      flavor_name      = "a2-ram4-disk0"
      image_name       = "Ubuntu 20.04 LTS Focal Fossa"
      system_user      = "ubuntu"
      boot_volume_size = 8

      rke2_version     = "v1.25.3+rke2r1"
      rke2_volume_size = 16
    }
  ]

  agents = [
    {
      name        = "pool-a"
      nodes_count = 1

      flavor_name      = "a2-ram4-disk0"
      image_name       = "Ubuntu 20.04 LTS Focal Fossa"
      system_user      = "ubuntu"
      boot_volume_size = 8

      rke2_version     = "v1.25.3+rke2r1"
      rke2_volume_size = 16
    }
  ]
}

terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
    }
  }
}
EOF

terraform init
terraform apply
# or, on upgrade, to process node by node
terraform apply -target='module.rke2.module.servers["0"]'
```

Note: it requires [rsync](https://rsync.samba.org) and
[yq](https://github.com/mikefarah/yq) to generate remote kube config file. You
can disable this behaviour by setting `ff_write_kubeconfig=false` and fetch
yourself `/etc/rancher/rke2/rke2.yaml` on server nodes.

## Infomaniak OpenStack [example](./example/main.tf)

A stable, performent and fully-equiped Kubernetes cluster in Switzerland for as
little as CHF 11.—/month (at the time of writing):

- nginx-ingress with floating ip (perfect under Cloudflare proxy)
- persistence through cinder-csi storage classes (retain, delete)
- 1 server 1cpu/2go (= master)
- 1 agent 1cpu/2go (= worker)

Quick benchmarks confirmed that the price/performance outperforms Scaleway
offering (but would need to be deepened).

| Flavour                                                      | CHF/month |
| ------------------------------------------------------------ | --------- |
| 2×2.93 (instances) + 0.09×2×(4+6) (blockstorage) + 3.34 (IP) | 11.—      |
| single 2cpu/4go server with 1x4cpu/8go worker                | ~25.—     |
| 3x2cpu/4go HA servers with 1x4cpu/8go worker                 | ~40.—     |
| 3x2cpu/4go HA servers with 3x8cpu/16go workers               | ~100.—    |

```bash
git clone git@github.com:zifeo/terraform-openstack-rke2.git && cd terraform-openstack-rke2/example
cat <<EOF > terraform.tfvars
tenant_name = "PCP-XXXXXXX"
user_name   = "PCU-XXXXXXX"
password    = "XXXXXXXXXXX"
EOF
terraform init
terraform apply # approx 2-3mins
kubectl --kubeconfig rke2.yaml get nodes
# NAME           STATUS   ROLES                       AGE     VERSION
# k8s-pool-a-1   Ready    <none>                      119s    v1.21.5+rke2r2
# k8s-server-1   Ready    control-plane,etcd,master   2m22s   v1.21.5+rke2r2
helm install wordpress --values wordpress.yaml --namespace default bitnami/wordpress
kubectl --kubeconfig rke2.yaml get pods -n default
# NAME                         READY   STATUS    RESTARTS   AGE
# wordpress-7474ddb77f-w6c86   1/1     Running   0          102s
# wordpress-mariadb-0          1/1     Running   0          102s
curl -s $(terraform output -raw floating_ip) -H 'host: wordpress.local' | grep Welcome
# <p>Welcome to WordPress. This is your first post. Edit or delete it, then start writing!</p>
```

See their technical [documentation](https://docs.infomaniak.cloud) and
[pricing](https://www.infomaniak.com/fr/hebergement/public-cloud/tarifs).

## More on RKE2 & OpenStack

[RKE2 cheatsheet](https://gist.github.com/superseb/3b78f47989e0dbc1295486c186e944bf)

```
# debug on nodes
alias crictl="sudo /var/lib/rancher/rke2/bin/crictl -r unix:///run/k3s/containerd/containerd.sock"
sudo systemctl status rke2-server

# restore s3 snapshot
sudo systemctl stop rke2-server
sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=BUCKET_NAME --etcd-s3-access-key=ACCESS_KEY --etcd-s3-secret-key=SECRET_KEY --cluster-reset-restore-path=SNAPSHOT_PATH
# reboot all nodes
```
