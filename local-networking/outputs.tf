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
