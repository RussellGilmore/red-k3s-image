####################################################################################################
# NLB: the only public entry point. 80/443 to agents (open), 6443 to the
# server (admin_cidrs only). TCP pass-through; TLS terminates in-cluster.
module "nlb" {
  source  = "RussellGilmore/red-lb/aws"
  version = "1.0.0"

  project_name       = var.cluster_name
  lb_name            = local.lb_name
  load_balancer_type = "network"
  vpc_id             = module.network.vpc_id
  subnet_ids         = values(module.network.subnet_ids)

  ingress_rules = [
    {
      description = "HTTP from anywhere"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS from anywhere"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "Kubernetes API from admins"
      from_port   = 6443
      to_port     = 6443
      protocol    = "tcp"
      cidr_blocks = var.admin_cidrs
    },
  ]

  target_groups = {
    api = {
      port                 = 6443
      protocol             = "TCP"
      deregistration_delay = 30
      cross_zone           = true # the server is in one AZ
      health_check         = { interval = 10 }
      targets              = { server = { id = module.server.instance_id } }
    }
    # Unhealthy until an ingress gateway listens on 80/443.
    http = {
      port                 = 80
      protocol             = "TCP"
      deregistration_delay = 30
      health_check         = { interval = 10 }
      targets              = { for k, m in module.agents : k => { id = m.instance_id } }
    }
    https = {
      port                 = 443
      protocol             = "TCP"
      deregistration_delay = 30
      health_check         = { interval = 10 }
      targets              = { for k, m in module.agents : k => { id = m.instance_id } }
    }
  }

  listeners = {
    api   = { port = 6443, protocol = "TCP", target_group = "api" }
    http  = { port = 80, protocol = "TCP", target_group = "http" }
    https = { port = 443, protocol = "TCP", target_group = "https" }
  }

  apex_domain = var.apex_domain
  dns_records = local.dns_records
}
