locals {
  ##################################################################################################
  # Placement

  # One entry per AZ, keyed by AZ letter ("a", "b", "c"): the AZ and its
  # index, which picks the subnet's /24 within vpc_cidr.
  azs = { for i, az in var.availability_zones : substr(az, -1, 1) => { az = az, index = i } }

  # The server runs in the first AZ, pinned to .10 in that AZ's subnet.
  server_az = substr(var.availability_zones[0], -1, 1)
  server_ip = cidrhost(cidrsubnet(var.vpc_cidr, 8, 0), 10)

  ##################################################################################################
  # Names

  server_name  = "${var.cluster_name}-server"
  agent_prefix = "${var.cluster_name}-agent"
  lb_name      = "${var.cluster_name}-nlb"

  # SSM path holding the join tokens.
  token_path = "/${var.cluster_name}"

  ##################################################################################################
  # Image and endpoints

  # The resolved AMI: ami_name when pinned, else the newest red-k3s-* image.
  ami_name = data.aws_ami.k3s.name

  # Public API endpoint (through the NLB) and the agents' private join URL.
  api_url    = "https://${var.domain}:6443"
  server_url = "https://${local.server_ip}:6443"

  # Every name aliased to the NLB.
  dns_records = concat([var.domain], var.app_hostnames)
}
