# Remote state bucket for the cluster root. Applied once with local state.
terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.47.0"
    }
  }
}

variable "project_name" {
  description = "Prefix for the state bucket (<project_name>-s3). S3 bucket names are global, so this must be unique."
  type        = string
}

variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "us-east-1"
}

provider "aws" {
  region = var.region
}

module "backend" {
  source  = "RussellGilmore/red-backend/aws"
  version = "3.0.0"

  project_name = var.project_name
}

output "state_bucket" {
  description = "Set this as bucket in cluster/backend.hcl."
  value       = module.backend.red_backend_s3_bucket
}
