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

    For local state, comment out the `backend "s3" {}` block in `versions.tf`,
    skip step 1, and run `terraform init` without `-backend-config`.

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
## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_admin_cidrs"></a> [admin\_cidrs](#input\_admin\_cidrs) | CIDRs allowed to reach the Kubernetes API through the NLB (e.g. ["203.0.113.10/32"]). | `list(string)` | n/a | yes |
| <a name="input_agent_instance_type"></a> [agent\_instance\_type](#input\_agent\_instance\_type) | Agent instance type (arm64). | `string` | `"t4g.medium"` | no |
| <a name="input_ami_name"></a> [ami\_name](#input\_ami\_name) | Exact AMI name to deploy. Empty uses the newest red-k3s-* AMI in this account; pin it after the first deploy. | `string` | `""` | no |
| <a name="input_apex_domain"></a> [apex\_domain](#input\_apex\_domain) | Public Route53 hosted zone the domain lives in (e.g. example.com). | `string` | n/a | yes |
| <a name="input_app_hostnames"></a> [app\_hostnames](#input\_app\_hostnames) | Extra hostnames to alias to the NLB as apps go live (no wildcard). | `list(string)` | `[]` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | AZs for the cluster: one public subnet and one agent each. The server runs in the first. | `list(string)` | <pre>[<br/>  "us-east-1a",<br/>  "us-east-1b",<br/>  "us-east-1c"<br/>]</pre> | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name prefix for every cluster resource. | `string` | `"red-k3s"` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | Kubernetes API hostname (e.g. cluster.example.com). Rendered into the server certificate and aliased to the NLB. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region. | `string` | `"us-east-1"` | no |
| <a name="input_server_instance_type"></a> [server\_instance\_type](#input\_server\_instance\_type) | Server instance type (arm64). | `string` | `"t4g.medium"` | no |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | VPC CIDR. Subnets are /24s carved from it; the server is pinned to .10 in the first. | `string` | `"10.30.0.0/16"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_agent_instance_ids"></a> [agent\_instance\_ids](#output\_agent\_instance\_ids) | Instance IDs of the agent nodes. |
| <a name="output_ami_name"></a> [ami\_name](#output\_ami\_name) | AMI the nodes run. Set ami\_name to this to pin it. |
| <a name="output_get_kubeconfig"></a> [get\_kubeconfig](#output\_get\_kubeconfig) | Command to fetch an admin kubeconfig (run from the repo root). |
| <a name="output_nlb_dns_name"></a> [nlb\_dns\_name](#output\_nlb\_dns\_name) | DNS name of the network load balancer. |
| <a name="output_server_instance_id"></a> [server\_instance\_id](#output\_server\_instance\_id) | Instance ID of the server node. |
<!-- END_TF_DOCS -->
<!-- prettier-ignore-end -->
