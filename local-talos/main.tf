locals {
  cluster_name = "klusse"


  # OpenEBS control plane replica count based on worker nodes
  openebs_control_plane_replicas = length(local.k8s_workers)
  # Enable replicated storage (requires 3+ worker nodes)
  enable_replicated_storage = local.openebs_control_plane_replicas >= 3

  # Node that does the talos cluster bootstrap
  bootstrap_node = "c1.k8s.kalski.xyz"

  control_plane_node_config = {
    "c1.k8s.kalski.xyz" = {
      install_disk  = "/dev/nvme0n1"
      install_image = "ghcr.io/talos-rpi5/installer:v1.11.5"
    }
    "c2.k8s.kalski.xyz" = {
      install_disk  = "/dev/nvme0n1"
      install_image = "ghcr.io/talos-rpi5/installer:v1.11.5"
    }
    "c3.k8s.kalski.xyz" = {
      install_disk  = "/dev/nvme0n1"
      install_image = "ghcr.io/talos-rpi5/installer:v1.11.5"
    }
  }

  # Node-specific configuration
  worker_node_config = {
    "w1.k8s.kalski.xyz" = {
      install_disk        = "/dev/nvme0n1"
      install_image       = "ghcr.io/siderolabs/installer:v1.11.5"
      storage_disks       = []
      storage_disk_serial = "S5GXNF0R218244B" # nvme2n1 for local-nvme StorageClass
    }
    "w2.k8s.kalski.xyz" = {
      install_disk = "/dev/nvme1n1"
      # Custom image from factory.talos.dev with nvidia extensions; regenerate when upgrading Talos
      install_image       = "factory.talos.dev/installer/6698d6f136c5bb37ca8bb8482c9084305084da0a5ead1f4dcae760796f8ab3a2:v1.11.6"
      nvidia_gpu          = true
      storage_disk_serial = "2450A7403637"
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
  endpoints            = [for hostname, node in local.control_plane_node_config : hostname]
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.controlplane.machine_configuration
  for_each                    = local.control_plane_node_config
  node                        = local.k8s_controlplanes[each.key].ip
  config_patches = [
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", merge({
      hostname = each.key
      },
      each.value
    )),
    file("${path.module}/patches/openebs-controlplane.yaml"),
    file("${path.module}/patches/metrics-controlplane.yaml")
  ]
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.salaisuudet.client_configuration
  machine_configuration_input = data.talos_machine_configuration.worker.machine_configuration
  for_each                    = local.worker_node_config
  node                        = local.k8s_workers[each.key].ip
  config_patches = concat([
    templatefile("${path.module}/templates/install-disk-and-hostname.yaml.tmpl", merge({
      hostname = each.key
      },
      each.value
    )),
    file("${path.module}/patches/openebs-worker.yaml"),
    file("${path.module}/patches/metrics-worker.yaml")
    ],
    lookup(each.value, "storage_disk_serial", null) != null ? [
      templatefile("${path.module}/templates/user-volume.yaml.tmpl", {
        storage_disk_serial = each.value.storage_disk_serial
      })
    ] : [],
    lookup(each.value, "nvidia_gpu", false) ? [
      file("${path.module}/patches/nvidia-worker.yaml")
    ] : []
  )
}

# WARNING:there should be just one of there per cluster
resource "talos_machine_bootstrap" "this" {
  depends_on           = [talos_machine_configuration_apply.controlplane]
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = local.k8s_controlplanes[local.bootstrap_node].ip
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on           = [talos_machine_bootstrap.this]
  client_configuration = talos_machine_secrets.salaisuudet.client_configuration
  node                 = local.k8s_controlplanes[local.bootstrap_node].ip
}

resource "helm_release" "openebs" {
  depends_on = [talos_cluster_kubeconfig.this]

  name             = "openebs"
  repository       = "https://openebs.github.io/openebs"
  chart            = "openebs"
  version          = "4.3.3"
  namespace        = "openebs"
  create_namespace = true
  atomic           = true

  set = [
    {
      name  = "engines.replicated.mayastor.enabled"
      value = tostring(local.enable_replicated_storage)
    },
    {
      name  = "engines.replicated.mayastor.csi.node.initContainers.enabled"
      value = "false" # Talos has nvme_tcp built-in
    },
    {
      name  = "loki.loki.commonConfig.replication_factor"
      value = tostring(min(local.openebs_control_plane_replicas, 3))
    },
    {
      name  = "loki.singleBinary.replicas"
      value = tostring(min(local.openebs_control_plane_replicas, 3))
    },
    {
      name  = "engines.local.lvm.enabled"
      value = "false"
    },
    {
      name  = "engines.local.zfs.enabled"
      value = "false"
    }
  ]
}

locals {
  # Flatten node storage configuration for disk pool creation
  storage_disks = flatten([
    for hostname, config in local.worker_node_config : [
      for idx, disk in lookup(config, "storage_disks", []) : {
        hostname = hostname
        disk     = disk
        name     = "${replace(hostname, ".", "-")}-pool-${idx}"
      }
    ]
  ])
}

resource "kubernetes_manifest" "diskpool" {
  for_each = local.enable_replicated_storage ? { for disk in local.storage_disks : disk.name => disk } : {}

  depends_on = [helm_release.openebs]

  manifest = {
    apiVersion = "openebs.io/v1beta2"
    kind       = "DiskPool"
    metadata = {
      name      = each.value.name
      namespace = "openebs"
    }
    spec = {
      node  = each.value.hostname
      disks = [each.value.disk]
    }
  }

  wait {
    fields = {
      "status.phase" = "Online"
    }
  }

  computed_fields = ["status"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "kubernetes_storage_class_v1" "local_nvme" {
  depends_on = [helm_release.openebs]

  metadata {
    name = "local-storage"
    annotations = {
      "openebs.io/cas-type"   = "local"
      "cas.openebs.io/config" = <<-EOT
        - name: StorageType
          value: "hostpath"
        - name: BasePath
          value: "/var/mnt/local-storage"
      EOT
    }
  }

  storage_provisioner    = "openebs.io/local"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  lifecycle {
    prevent_destroy = true
  }
}

# Uncomment when Mayastor is enabled (requires 3+ worker nodes)
# resource "kubernetes_storage_class_v1" "replicated" {
#   depends_on = [helm_release.openebs]
#
#   metadata {
#     name = "replicated"
#   }
#
#   storage_provisioner    = "io.openebs.csi-mayastor"
#   volume_binding_mode    = "WaitForFirstConsumer"
#   allow_volume_expansion = true
#
#   parameters = {
#     repl      = "2"
#     protocol  = "nvme"
#     ioTimeout = "30"
#   }
# }
