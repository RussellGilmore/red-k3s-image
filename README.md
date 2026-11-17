# Red K3s Image

## [![Red K3s Image](https://github.com/RussellGilmore/red-k3s-image/actions/workflows/build-ami.yml/badge.svg?branch=main)](https://github.com/RussellGilmore/red-k3s-image/actions/workflows/build-ami.yml)

A Packer-built AWS AMI for [k3s](https://k3s.io/) clusters: one image that boots
as a control-plane server or a worker agent, joins over private networking, and
pulls its secrets from SSM at first boot. It is designed to be deployed with the
red Terraform modules, and [`examples/terraform`](./examples/terraform) builds a
complete multi-AZ cluster from nothing but those modules.

## Features

- **One image, two roles.** k3s is installed with both a server and an agent
  unit, neither started at bake time. `K3S_ROLE` in user-data picks one at first
  boot.
- **Nothing secret or unique is baked in.** No node identity, tokens, TLS
  material or iSCSI initiator name ships in the AMI; every instance generates
  its own.
- **Tokens from SSM, never user-data.** First boot reads the join tokens from
  SSM Parameter Store into root-only files. User-data carries parameter names
  only.
- **Private joins.** Agents join the server's private IP, so join traffic never
  leaves the VPC and the API needs no public exposure.
- **Embedded etcd** from the first boot.
- **Zone-aware.** Nodes are labeled with their region and AZ from IMDS, ready
  for topology spread and zone-aware storage.
- **Workloads on agents only.** The server is tainted
  `CriticalAddonsOnly=true:NoExecute`; ServiceLB runs only on agents.
- **Ready for Istio and the Gateway API.** Traefik and k3s's bundled Gateway API
  CRDs are disabled, so the CRDs can be installed version-matched to Istio.
- **Longhorn-ready.** open-iscsi, NFS client, cryptsetup and the required kernel
  modules are pre-installed.
- **Hardened access.** SSM Session Manager only (no SSH keys), IMDSv2, encrypted
  root volume. The AWS CLI and Helm are installed at pinned versions.
- **Idempotent first boot.** Safe to re-run by hand after a partial failure;
  agents that boot before the server keep retrying until it is reachable.

## Built for the red Terraform modules

Each layer of a cluster maps onto a red module:

| Layer                      | Module                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------- |
| Remote state               | [red-backend](https://registry.terraform.io/modules/RussellGilmore/red-backend/aws)   |
| VPC and one subnet per AZ  | [red-network](https://registry.terraform.io/modules/RussellGilmore/red-network/aws)   |
| Server and agents          | [red-instance](https://registry.terraform.io/modules/RussellGilmore/red-instance/aws) |
| Public entry point and DNS | [red-lb](https://registry.terraform.io/modules/RussellGilmore/red-lb/aws)             |

The image's runtime needs line up with what the modules provide:

- red-instance pins the server's private IP (`private_ip`), which agents join
  by; attaches the token-reading IAM policy before launch
  (`additional_iam_policy_json`); and passes the user-data that selects the
  role.
- red-lb fronts the cluster with an NLB: 80/443 to the agents, the Kubernetes
  API to the server for admin CIDRs only, plus the DNS alias for the API name.
  Nodes admit traffic only from the NLB's security group.
- red-network provides the multi-AZ subnets the agents spread across.

```
                 Internet
                    │
        ┌───────────┴───────────┐
        │   NLB (red-lb)        │   80/443 public · 6443 admin only
        └───┬───────────────┬───┘
            │ 6443          │ 80/443
     ┌──────┴─────┐   ┌─────┴──────────────────────────┐
     │  server    │◄──┤ agent-a   agent-b   agent-c    │  (red-instance)
     │ pinned IP  │   │ one per AZ, private join       │
     └────────────┘   └────────────────────────────────┘
         VPC with one public subnet per AZ (red-network)
```

See [`examples/terraform`](./examples/terraform) to deploy it.

## Runtime configuration contract

Cloud-init writes `/etc/red-k3s/first-boot.env` and runs
`/usr/local/sbin/red-k3s-first-boot.sh`.

| Variable                 | Server   | Agent    | Description                                        |
| ------------------------ | -------- | -------- | -------------------------------------------------- |
| `K3S_ROLE`               | required | required | `server` or `agent`                                |
| `DOMAIN`                 | required | —        | API hostname, rendered into the server certificate |
| `K3S_SERVER_URL`         | —        | required | `https://<server-private-ip>:6443`                 |
| `K3S_SERVER_TOKEN_PARAM` | required | —        | SSM parameter name of the server token             |
| `K3S_AGENT_TOKEN_PARAM`  | required | required | SSM parameter name of the agent token              |
| `ENABLE_TRAEFIK`         | optional | —        | `false` (default)                                  |

Progress is logged to `/var/log/red-k3s-first-boot.log`; completion is marked by
`/var/lib/red-k3s/first-boot.done`.

## Build

Requires Packer >= 1.14.0, AWS credentials, a build subnet with outbound
internet access, and an instance profile with `AmazonSSMManagedInstanceCore`
(see [Build IAM](#build-iam)).

```bash
cp example.pkrvars.hcl build.auto.pkrvars.hcl   # gitignored; edit values
packer init .
packer validate .
packer build .
```

Versions of k3s, Helm and the AWS CLI are pinned in `variables.pkr.hcl` and
tagged on the AMI.

## Build IAM

Packer connects to the build instance over Session Manager, so the build needs
an instance profile with SSM permissions:

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

Pass the profile name via `iam_instance_profile` in your vars file.

## Accessing the cluster

[`scripts/get-kubeconfig.sh`](./scripts/get-kubeconfig.sh) fetches the admin
kubeconfig over SSM, points it at your API name and writes it `0600`:

```bash
scripts/get-kubeconfig.sh -u https://cluster.example.com:6443
```

The kubeconfig is a cluster-admin credential. Never commit it.
