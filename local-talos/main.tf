locals {
  cluster_name = "klusse"

  # Node-specific configuration
  node_config = {
    "c1.k8s.kalski.xyz" = {
      talos_install_disk = "/dev/mmcblk0"
    }
    "w1.k8s.kalski.xyz" = {
      talos_install_disk = "/dev/nvme1n1"
    }
  }
}

resource "talos_machine_secrets" "salaisuudet" {
  talos_version = "1.10"
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.networking.cluster_config.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.salaisuudet.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.networking.cluster_config.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.salaisuudet.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  endpoints            = [for hostname, node in local.networking.k8s_controlplanes : node.ip]
  nodes                = [[for hostname, node in local.networking.k8s_controlplanes : node.ip][0]]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  for_each                    = local.networking.k8s_controlplanes
  node                        = each.value.ip
  config_patches = [
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", {
      hostname     = each.key
      install_disk = local.node_config[each.key].talos_install_disk
    })
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  for_each                    = local.networking.k8s_workers
  node                        = each.value.ip
  config_patches = [
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", {
      hostname     = each.key
      install_disk = local.node_config[each.key].talos_install_disk
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = [for hostname, node in local.networking.k8s_controlplanes : node.ip][0]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = [for hostname, node in local.networking.k8s_controlplanes : node.ip][0]
}
