locals {
  cluster_name = "klusse"

  # Node-specific configuration
  node_config = {
    "c1.k8s.kalski.xyz" = {
      install_disk  = "/dev/nvme0n1"
      install_image = "ghcr.io/talos-rpi5/installer:v1.10.6-rpi5"
    }
    "w1.k8s.kalski.xyz" = {
      install_disk  = "/dev/nvme1n1"
      install_image = "ghcr.io/siderolabs/installer:v1.10.6"
    }
  }
}

resource "talos_machine_secrets" "salaisuudet" {
  talos_version = "1.10"
}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.salaisuudet.machine_secrets
}

data "talos_machine_configuration" "worker" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.salaisuudet.machine_secrets
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  endpoints            = [for hostname, node in local.k8s_controlplanes : node.ip]
  nodes                = [[for hostname, node in local.k8s_controlplanes : node.ip][0]]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  for_each                    = local.k8s_controlplanes
  node                        = each.value.ip
  config_patches = [
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", merge({
      hostname = each.key
      },
      local.node_config[each.key]
    ))
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  for_each                    = local.k8s_workers
  node                        = each.value.ip
  config_patches = [
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", merge({
      hostname = each.key
      },
      local.node_config[each.key]
    ))
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = [for hostname, node in local.k8s_controlplanes : node.ip][0]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = [for hostname, node in local.k8s_controlplanes : node.ip][0]
}
