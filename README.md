# Terraform RKE2 OpenStack

Heavily inspired from [remche/terraform-openstack-rke2](https://github.com/remche/terraform-openstack-rke2).

## Features

- : https://docs.rke2.io
-
-

### Next

- distinct subnet for servers and agents
- loadbalancer auto-provisions
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
  source = "./rke2"

  name = "k8s"

  public_net_name = "ext-floating1"
  rules_ext = [
    { "port" : 22, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 80, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
    { "port" : 6443, "protocol" : "tcp", "source" : "0.0.0.0/0" },
  ]

  server = {
    nodes_count = 1

    flavor_name      = "a2-ram4-disk0"
    image_name       = "Ubuntu 20.04 LTS Focal Fossa"
    system_user      = "ubuntu"
    boot_volume_size = 8

    rke2_version     = "v1.21.5+rke2r2"
    rke2_volume_size = 16
  }

  agents = [
    {
      name        = "pool-a"
      nodes_count = 1

      flavor_name      = "a2-ram4-disk0"
      image_name       = "Ubuntu 20.04 LTS Focal Fossa"
      system_user      = "ubuntu"
      boot_volume_size = 8

      rke2_version     = "v1.21.5+rke2r2"
      rke2_volume_size = 16
    }
  ]
}

terraform {
  required_version = ">= 0.14.0"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = ">=3.1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">=2.1.2"
    }
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.35.0"
    }
  }
}
EOF
```

```bash
terraform init
terraform apply
# or, on upgrade, to process node by node
terraform apply -parallelism=1
```

## Infomaniak [example](./infomaniak.tf)

2×2.93 (instances) + 0.09×2×(4+6) (blockstorage) + 3.34 (IP) = CHF 11.—/month

Single server with 1x4cpu/8go workers : ~25.—/month
3 HA servers with 1x4cpu/8go workers : ~40.—/month
3 HA servers with 3x8cpu/16go workers : ~100.—/month

Technical documentation: https://docs.infomaniak.cloud

```bash
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

## More

[RKE2 cheatsheet](https://gist.github.com/superseb/3b78f47989e0dbc1295486c186e944bf)

```
# debug on nodes
alias docker=sudo /var/lib/rancher/rke2/bin/crictl -r /run/k3s/containerd/containerd.sock
```
