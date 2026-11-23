terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.0"
    }
  }

  # Remote state in the red-backend bucket. Values come from backend.hcl:
  #   terraform init -backend-config=backend.hcl
  #
  # To use local state instead, comment out this block and run a plain
  # `terraform init`. The ../backend root is then not needed. To move to the
  # remote backend later, restore the block and run:
  #   terraform init -backend-config=backend.hcl -migrate-state
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Orchestrator = "Terraform"
      Project      = var.cluster_name
    }
  }
}
