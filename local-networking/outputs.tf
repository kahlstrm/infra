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

output "cluster_config" {
  description = "Kubernetes cluster configuration"
  value = {
    cluster_endpoint = "https://${values(local.k8s_control_plane_nodes)[0].ip}:6443"
    network          = local.minirack.network
  }
}

