####################################################################################################
# Required
variable "domain" {
  description = "Kubernetes API hostname (e.g. cluster.example.com). Rendered into the server certificate and aliased to the NLB."
  type        = string

  validation {
    condition     = endswith(var.domain, ".${var.apex_domain}")
    error_message = "domain must be a name inside apex_domain."
  }
}

variable "apex_domain" {
  description = "Public Route53 hosted zone the domain lives in (e.g. example.com)."
  type        = string
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the Kubernetes API through the NLB (e.g. [\"203.0.113.10/32\"])."
  type        = list(string)

  validation {
    condition = length(var.admin_cidrs) > 0 && alltrue([
      for c in var.admin_cidrs : can(cidrhost(c, 0)) && c != "0.0.0.0/0"
    ])
    error_message = "admin_cidrs must be one or more valid CIDRs, and never 0.0.0.0/0."
  }
}

####################################################################################################
# Optional
variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for every cluster resource."
  type        = string
  default     = "red-k3s"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,14}$", var.cluster_name))
    error_message = "cluster_name must be 1-15 lowercase letters, digits or hyphens (load balancer name limits)."
  }
}

variable "ami_name" {
  description = "Exact AMI name to deploy. Empty uses the newest red-k3s-* AMI in this account; pin it after the first deploy."
  type        = string
  default     = ""
}

variable "availability_zones" {
  description = "AZs for the cluster: one public subnet and one agent each. The server runs in the first."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "vpc_cidr" {
  description = "VPC CIDR. Subnets are /24s carved from it; the server is pinned to .10 in the first."
  type        = string
  default     = "10.30.0.0/16"
}

variable "server_instance_type" {
  description = "Server instance type (arm64)."
  type        = string
  default     = "t4g.medium"
}

variable "agent_instance_type" {
  description = "Agent instance type (arm64)."
  type        = string
  default     = "t4g.medium"
}

variable "app_hostnames" {
  description = "Extra hostnames to alias to the NLB as apps go live (no wildcard)."
  type        = list(string)
  default     = []
}
