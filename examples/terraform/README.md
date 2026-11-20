# red-k3s cluster example

One server and one agent per AZ behind an NLB, built entirely from red modules:
[red-backend](https://registry.terraform.io/modules/RussellGilmore/red-backend/aws),
[red-network](https://registry.terraform.io/modules/RussellGilmore/red-network/aws),
[red-instance](https://registry.terraform.io/modules/RussellGilmore/red-instance/aws),
[red-lb](https://registry.terraform.io/modules/RussellGilmore/red-lb/aws).

## Prerequisites

- An AMI built from this repo (`packer build .` at the repo root)
- A public Route53 hosted zone for `apex_domain`
- Terraform >= 1.15.0, AWS CLI, Session Manager plugin, kubectl

## Required variables

| Variable       | Root      | Description                                                                |
| -------------- | --------- | -------------------------------------------------------------------------- |
| `project_name` | `backend` | Prefix for the state bucket (`<project_name>-s3`); must be globally unique |
| `domain`       | `cluster` | API hostname, e.g. `cluster.example.com`                                   |
| `apex_domain`  | `cluster` | Hosted zone, e.g. `example.com`                                            |
| `admin_cidrs`  | `cluster` | CIDRs allowed to reach the Kubernetes API                                  |

## Admin IP

```bash
curl -s https://checkip.amazonaws.com
```

Set `admin_cidrs = ["<that IP>/32"]`. When your IP changes, update it and
`terraform apply`.

## Deploy

1. **State bucket**

    ```bash
    cd backend
    terraform init
    terraform apply -var project_name=<unique-name>
    ```

    Keep `backend/terraform.tfstate`; it tracks the bucket itself.

2. **Cluster**

    ```bash
    cd ../cluster
    cp backend.hcl.example backend.hcl            # set bucket from step 1
    cp terraform.tfvars.example terraform.tfvars  # set required variables
    terraform init -backend-config=backend.hcl
    terraform apply
    ```

3. **Pin the AMI.** Set `ami_name` to the `ami_name` output. Unpinned, a newer
   `red-k3s-*` AMI replaces every node on the next apply (a new cluster).

4. **Kubeconfig**

    ```bash
    ../../../scripts/get-kubeconfig.sh -u https://<domain>:6443
    ```

## Destroy

```bash
cd cluster && terraform destroy
```

Destroy `backend` last, after emptying the bucket (it is versioned).

## AWS Resources

<!-- prettier-ignore-start -->
<!-- BEGIN_TF_DOCS -->


<!-- END_TF_DOCS -->
<!-- prettier-ignore-end -->
