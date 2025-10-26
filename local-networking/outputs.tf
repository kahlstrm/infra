output "k8s_controlplanes" {
  description = "Kubernetes control plane nodes"
  value = { for hostname, config in local.k8s_control_plane_nodes : hostname => {
    ip = config.ip
  } }
}

output "k8s_workers" {
  description = "Kubernetes worker nodes"
  value = { for hostname, config in local.k8s_worker_nodes : hostname => {
    ip = config.ip
  } }
}

output "cluster_network" {
  description = "Kubernetes cluster network"
  value       = local.kuberack_network.network
}

output "secret_id" {
  description = "Google Secret Manager secret ID for cross-layer access"
  value       = module.secrets.secret_id
}

output "external_dns_username" {
  description = "MikroTik external-dns service account username"
  value       = "external-dns"
}

output "kuberack_domain" {
  description = "Kuberack RB5009 domain name for API access"
  value       = local.kuberack_rb5009.domain_name
}
