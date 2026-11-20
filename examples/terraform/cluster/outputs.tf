output "ami_name" {
  description = "AMI the nodes run. Set ami_name to this to pin it."
  value       = local.ami_name
}

output "server_instance_id" {
  description = "Instance ID of the server node."
  value       = module.server.instance_id
}

output "agent_instance_ids" {
  description = "Instance IDs of the agent nodes."
  value       = { for k, m in module.agents : k => m.instance_id }
}

output "nlb_dns_name" {
  description = "DNS name of the network load balancer."
  value       = module.nlb.lb_dns_name
}

output "get_kubeconfig" {
  description = "Command to fetch an admin kubeconfig (run from the repo root)."
  value       = "scripts/get-kubeconfig.sh -n ${local.server_name} -u ${local.api_url} -o ~/.kube/${var.cluster_name}.yaml"
}
