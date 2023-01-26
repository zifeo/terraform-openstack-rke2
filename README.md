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

  floating_pool  = "ext-floating1"
  rules_ssh_cidr = "0.0.0.0/0"
  rules_k8s_cidr = "0.0.0.0/0"

  bootstrap = true
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
terraform apply -target='module.rke2.module.servers["server-a"]'
```

See [example](./example/main.tf) for more options.

Note: it requires [rsync](https://rsync.samba.org) and
[yq](https://github.com/mikefarah/yq) to generate remote kube config file. You
can disable this behaviour by setting `ff_write_kubeconfig=false` and fetch
yourself `/etc/rancher/rke2/rke2.yaml` on server nodes.

## Infomaniak OpenStack

A stable, performent and fully-equiped Kubernetes cluster in Switzerland for as
little as CHF 11.—/month (at the time of writing):

- nginx-ingress with floating ip (perfect under Cloudflare proxy)
- persistence through cinder-csi storage classes (retain, delete)
- 1 server 1cpu/2go (= master)
- 1 agent 1cpu/2go (= worker)

Quick benchmarks confirmed that the price/performance outperforms Scaleway
offering (but would need to be deepened).

| Flavour                                                                           | CHF/month |
| --------------------------------------------------------------------------------- | --------- |
| 2×2.93 (instances) + 0.09×2×(4+6) (blockstorage) + 3.34 (IP) + HA (load-balancer) | 21.—      |
| single 2cpu/4go server with 1x4cpu/8go worker                                     | ~35.—     |
| 3x2cpu/4go HA servers with 1x4cpu/8go worker                                      | ~50.—     |
| 3x2cpu/4go HA servers with 3x8cpu/16go workers                                    | ~110.—    |

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
# find version of bundled components
grep -r -A 1 repository: . 

# debug on nodes
crictl
sudo systemctl status rke2-server

# restore s3 snapshot
sudo systemctl stop rke2-server && sudo rke2 server --cluster-reset --etcd-s3 --etcd-s3-bucket=BUCKET_NAME --etcd-s3-access-key=ACCESS_KEY --etcd-s3-secret-key=SECRET_KEY --cluster-reset-restore-path=SNAPSHOT_PATH && sudo reboot
# remove db on other server nodes
# sudo systemctl stop rke2-server && sudo rm -rf /var/lib/rancher/rke2/server/db && sudo reboot
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
