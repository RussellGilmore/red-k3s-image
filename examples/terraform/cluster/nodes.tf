####################################################################################################
# Server: pinned private IP, no public address for inbound. Agents reach it
# over the VPC; admins reach it through the NLB.
module "server" {
  source  = "RussellGilmore/red-instance/aws"
  version = "2.5.0"

  project_name  = var.cluster_name
  instance_name = "${var.cluster_name}-server"

  ami_name      = data.aws_ami.k3s.name
  ami_owner     = "self"
  instance_type = var.server_instance_type
  volume_size   = 50

  create_vpc   = false
  vpc_id       = module.network.vpc_id
  subnet_id    = module.network.subnet_ids["public_${local.server_az}"]
  private_ip   = local.server_ip
  allocate_eip = false

  # Reads both tokens at first boot (default aws/ssm KMS key).
  additional_iam_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = [aws_ssm_parameter.server_token.arn, aws_ssm_parameter.agent_token.arn]
    }]
  })

  ingress_rules = [
    {
      description = "k3s API/supervisor from agents"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    },
    {
      description     = "k3s API from the NLB"
      from_port       = 6443
      to_port         = 6443
      protocol        = "tcp"
      security_groups = [module.nlb.security_group_id]
    },
    {
      description = "kubelet"
      from_port   = 10250
      to_port     = 10250
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    },
    {
      description = "flannel VXLAN"
      from_port   = 8472
      to_port     = 8472
      protocol    = "udp"
      cidr_blocks = [var.vpc_cidr]
    },
  ]

  user_data = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/red-k3s/first-boot.env
        owner: root:root
        permissions: "0600"
        content: |
          K3S_ROLE=server
          DOMAIN=${var.domain}
          K3S_SERVER_TOKEN_PARAM=${aws_ssm_parameter.server_token.name}
          K3S_AGENT_TOKEN_PARAM=${aws_ssm_parameter.agent_token.name}
    runcmd:
      - [ /usr/local/sbin/red-k3s-first-boot.sh ]
  EOF
}

####################################################################################################
# Agents: one per AZ, joining the server over its pinned private IP.
module "agents" {
  source   = "RussellGilmore/red-instance/aws"
  version  = "2.5.0"
  for_each = local.azs

  project_name  = var.cluster_name
  instance_name = "${var.cluster_name}-agent-${each.key}"

  ami_name      = data.aws_ami.k3s.name
  ami_owner     = "self"
  instance_type = var.agent_instance_type
  volume_size   = 50

  create_vpc   = false
  vpc_id       = module.network.vpc_id
  subnet_id    = module.network.subnet_ids["public_${each.key}"]
  allocate_eip = false

  # Reads the agent token only.
  additional_iam_policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = aws_ssm_parameter.agent_token.arn
    }]
  })

  ingress_rules = [
    {
      description     = "HTTP from the NLB"
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      security_groups = [module.nlb.security_group_id]
    },
    {
      description     = "HTTPS from the NLB"
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [module.nlb.security_group_id]
    },
    {
      description = "kubelet"
      from_port   = 10250
      to_port     = 10250
      protocol    = "tcp"
      cidr_blocks = [var.vpc_cidr]
    },
    {
      description = "flannel VXLAN"
      from_port   = 8472
      to_port     = 8472
      protocol    = "udp"
      cidr_blocks = [var.vpc_cidr]
    },
  ]

  user_data = <<-EOF
    #cloud-config
    write_files:
      - path: /etc/red-k3s/first-boot.env
        owner: root:root
        permissions: "0600"
        content: |
          K3S_ROLE=agent
          K3S_SERVER_URL=https://${module.server.private_ip}:6443
          K3S_AGENT_TOKEN_PARAM=${aws_ssm_parameter.agent_token.name}
    runcmd:
      - [ /usr/local/sbin/red-k3s-first-boot.sh ]
  EOF
}
