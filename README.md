# Red K3s Image

## [![Red K3s Image](https://github.com/RussellGilmore/red-k3s-image/actions/workflows/build-ami.yml/badge.svg?branch=main)](https://github.com/RussellGilmore/red-k3s-image/actions/workflows/build-ami.yml)

Packer configuration that builds an AWS AMI running a single-node
[k3s](https://k3s.io/) cluster with embedded etcd, ready for Istio and the
Kubernetes Gateway API. Traefik is disabled by default but can be enabled if
needed.

## Overview

This image bakes in k3s and Helm at pinned versions and defers all
cluster-specific configuration to first boot via cloud-init. Launch it for any
domain by supplying values through EC2 user-data.

Key design points:

-   **Ubuntu 26.04 LTS (Resolute), arm64/Graviton** base, rebuilt from the
    newest Canonical image at each bake.
-   **k3s installed but never started at bake time.** Starting k3s during the
    build would bake the node identity, cluster token and TLS material into the
    AMI, shared by every instance launched from it. The service is enabled and
    started at first boot instead.
-   **Embedded etcd from the start** (`cluster-init: true`), so additional
    servers can join later without a datastore migration.
-   **Traefik disabled by default.** It can be enabled if needed.
-   **API reachable by name.** The cluster's FQDN is rendered into `tls-san`, so
    a kubeconfig pointed at that name verifies cleanly against the k3s CA.
-   **SSM-only access.** No SSH key pair; reach the instance through AWS Session
    Manager. IMDSv2 required, root volume encrypted.
-   **Idempotent first boot.** The script marks a sentinel on completion and is
    a no-op on re-run, so it can be safely re-run by hand after a partial
    failure.

## Components

Baked into the image:

-   `k3s` at a pinned version (installed, disabled and inactive until first
    boot)
-   `helm` at a pinned version
-   A k3s config template (`/etc/red-k3s/config.yaml.tmpl`), with the domain
    slotted in and the `disable:` block appended at first boot
-   A first-boot script (`/usr/local/sbin/red-k3s-first-boot.sh`) driven by
    cloud-init
-   A system-wide `KUBECONFIG` export for root shells

## Prerequisites

-   Packer >= 1.14.0
-   AWS credentials configured (env vars, shared config, or instance profile)
-   A build VPC/subnet with outbound internet access
-   An IAM instance profile for the build with `AmazonSSMManagedInstanceCore`
    (Packer connects via Session Manager — see [Build IAM](#build-iam))

## Build

Copy the example vars file, fill in your build networking, and build:

```bash
cp example.pkrvars.hcl build.auto.pkrvars.hcl   # gitignored; edit values
packer init .
packer fmt -check .
packer validate .
packer build .
```

The build prints the resulting AMI ID on completion. See `variables.pkr.hcl` for
all available build variables, including the `k3s_version` and `helm_version`
pins.

## Build IAM

The build instance connects via AWS Session Manager (no SSH keys), so it needs
an instance profile with SSM permissions. Create this once in your account
before building:

```hcl
resource "aws_iam_role" "packer_build" {
  name        = "PackerBuildRole"
  description = "Role assumed by Packer build instances for SSM connectivity"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "packer_build_ssm" {
  role       = aws_iam_role.packer_build.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "packer_build" {
  name = aws_iam_role.packer_build.name
  role = aws_iam_role.packer_build.name
}
```

Pass the instance profile name to the build via the `iam_instance_profile`
variable (see `example.pkrvars.hcl`). The identity you run Packer with (your AWS
credentials) also needs permissions to launch instances, create AMIs and
snapshots, and manage temporary build resources — see the
[Packer AWS documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon#iam-task-or-instance-role)
for the minimal build policy.

## Runtime configuration contract

At first boot, cloud-init (from the instance's user-data) must write
`/etc/red-k3s/first-boot.env` and invoke the first-boot script. The env file
supports:

| Variable         | Required | Description                                                                                                 |
| ---------------- | :------: | ----------------------------------------------------------------------------------------------------------- |
| `DOMAIN`         |   yes    | FQDN for the cluster's API endpoint; rendered into `tls-san`. Must match the A record pointing at the node. |
| `K3S_ROLE`       |    no    | `server` (default). `agent` is reserved and currently exits with an error.                                  |
| `ENABLE_TRAEFIK` |    no    | `false` (default). Set `true` to keep k3s's bundled Traefik instead of using Istio for ingress.             |

First boot renders `/etc/rancher/k3s/config.yaml`, starts k3s, waits for the API
and the node to reach Ready, then writes `/var/lib/red-k3s/first-boot.done`.
Progress is logged to `/var/log/red-k3s-first-boot.log`.

## Deploying with red-instance

This image pairs with the
[terraform-aws-red-instance](https://github.com/RussellGilmore/terraform-aws-red-instance)
module, which provides the `user_data` input this image needs.

A cloud-config user-data template (`k3s-user-data.yaml.tftpl`) writes the env
file and runs first-boot:

```yaml
#cloud-config
write_files:
    - path: /etc/red-k3s/first-boot.env
      owner: root:root
      permissions: "0600"
      content: |
          DOMAIN=${cluster_domain}
          K3S_ROLE=server
          ENABLE_TRAEFIK=false

runcmd:
    - /usr/local/sbin/red-k3s-first-boot.sh
```

And the module call:

```hcl
module "k3s_cluster" {
  source = "git::https://github.com/RussellGilmore/terraform-aws-red-instance.git?ref=v2.2.0"

  project_name  = "red-space"
  instance_name = "Cluster"

  instance_type = "t4g.medium"
  ami_name      = "red-k3s-*"        # matches the Packer ami_name_prefix
  ami_owner     = var.k3s_ami_owner  # your account ID (you built the AMI)
  volume_size   = 50

  # Standalone: the module provisions its own public VPC.
  create_vpc        = true
  availability_zone = "us-east-1f"
  allocate_eip      = true

  # Kubernetes API plus HTTP/HTTPS for the Istio gateway. No SSH (SSM-only).
  # Node-to-node ports (8472/udp VXLAN, 10250/tcp kubelet) are intentionally
  # absent: they are not needed on a single node and must never be public.
  ingress_rules = [
    {
      description = "Kubernetes API"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTP via Istio gateway"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS via Istio gateway"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]

  # Rendered user-data carrying the cluster domain.
  user_data = templatefile("${path.module}/k3s-user-data.yaml.tftpl", {
    cluster_domain = "cluster.example.com"
  })

  # Public DNS A record for the API endpoint. Must match DOMAIN above, or
  # the name will not appear in the API server certificate's SANs.
  enable_public_dns = true
  apex_domain       = "example.com"
  dns_name          = "cluster.example.com"
}
```

## Accessing the cluster

The kubeconfig is written with mode `0600`, so use a root shell over SSM:

```bash
sudo -i
kubectl get nodes
helm list -A
```

To use it from a workstation, copy `/etc/rancher/k3s/k3s.yaml` locally and
replace `127.0.0.1` with the cluster's FQDN:

```bash
kubectl --kubeconfig ./cluster.yaml get nodes
```

No TLS workaround is needed. The kubeconfig carries the k3s cluster CA and the
FQDN is covered by the API server certificate's SANs via `tls-san`.

## Roadmap

-   Agent role support (`K3S_ROLE=agent`), with the join token delivered via SSM
    Parameter Store rather than user-data
-   Istio and Gateway API install guidance for the post-cluster bootstrap
