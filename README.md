# Red K3s Image

Packer configuration that builds an AWS AMI containing K3s and cert-manager,
ready for single-node cluster bootstrap via EC2 user_data.

## Overview

The AMI ships with K3s and Helm installed but the K3s service disabled. On first
boot, a systemd oneshot unit reads configuration from user_data (`DOMAIN`,
`EMAIL`, `LE_ENV`), starts K3s, installs cert-manager, provisions a Let's
Encrypt certificate for the Kubernetes API, and rotates the K3s CA so kubectl
connects over a publicly-trusted TLS chain.

## Components

| Component    | Version             |
| ------------ | ------------------- |
| Ubuntu       | 24.04 (Noble) arm64 |
| K3s          | v1.34.6+k3s1        |
| cert-manager | v1.20.2             |

## Prerequisites

-   Packer >= 1.14.0
-   AWS credentials configured (env vars, shared config, or instance profile)
-   Permissions to create AMIs, snapshots, key pairs, security groups, and EC2
    instances in the target region

## Build

```bash
packer init .
packer fmt -check .
packer validate -var-file=example.pkrvars.hcl .
packer build -var-file=example.pkrvars.hcl .
```

## Repository layout

-   `versions.pkr.hcl` — required Packer version and plugins
-   `variables.pkr.hcl` — input variable declarations
-   `k3s.pkr.hcl` — source AMI lookup and build definition
-   `example.pkrvars.hcl` — example variable values
-   `scripts/` — provisioner scripts (Phase 2+)
-   `files/` — static assets staged onto the AMI (Phase 4+)
