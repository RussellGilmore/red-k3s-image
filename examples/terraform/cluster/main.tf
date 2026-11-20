# Newest red-k3s AMI built in this account, unless ami_name pins one.
data "aws_ami" "k3s" {
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = [var.ami_name != "" ? var.ami_name : "red-k3s-*"]
  }
}

####################################################################################################
# Network: one public subnet per AZ, no NAT gateway.
module "network" {
  source  = "RussellGilmore/red-network/aws"
  version = "3.0.0"

  project_name = var.cluster_name
  vpc_name     = "${var.cluster_name}-vpc"
  vpc_cidr     = var.vpc_cidr

  subnets = {
    for k, v in local.azs : "public_${k}" => {
      name              = "${var.cluster_name}-public-${k}"
      cidr_block        = cidrsubnet(var.vpc_cidr, 8, v.index)
      availability_zone = v.az
      type              = "public"
    }
  }

  create_nat_gateway = false
}

####################################################################################################
# Join tokens: generated ephemerally and written to SSM write-only, so they
# never appear in Terraform state or plan output. Bump value_wo_version to rotate.
ephemeral "random_password" "server_token" {
  length  = 48
  special = false
}

ephemeral "random_password" "agent_token" {
  length  = 48
  special = false
}

resource "aws_ssm_parameter" "server_token" {
  name             = "${local.token_path}/server-token"
  description      = "k3s server token for ${var.cluster_name}"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.server_token.result
  value_wo_version = 1
}

resource "aws_ssm_parameter" "agent_token" {
  name             = "${local.token_path}/agent-token"
  description      = "k3s agent token for ${var.cluster_name}"
  type             = "SecureString"
  value_wo         = ephemeral.random_password.agent_token.result
  value_wo_version = 1
}
