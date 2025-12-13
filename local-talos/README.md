# Talos Kubernetes Cluster Bootstrap

This directory contains Terraform configuration to bootstrap a Talos Linux Kubernetes cluster.

## Prerequisites

1. `local-networking` layer applied first
2. Talos Linux nodes booted from ISO and accessible on network

## Bootstrapping a New Cluster

### 1. Identify Installation Disks

Check available disks on each node:

```bash
talosctl get disks --insecure --nodes <node-ip>
```

### 2. Update Node Configuration

Edit `main.tf` and update the `control_plane_node_config` and `worker_node_config` locals with the correct disk paths and installer images:

```hcl
bootstrap_node = "c1.k8s.kalski.xyz"

control_plane_node_config = {
  "c1.k8s.kalski.xyz" = {
    install_disk  = "/dev/nvme0n1"
    install_image = "ghcr.io/talos-rpi5/installer:v1.11.5"
  }
}

worker_node_config = {
  "w1.k8s.kalski.xyz" = {
    install_disk  = "/dev/nvme0n1"
    install_image = "ghcr.io/siderolabs/installer:v1.11.5"
  }
}
```

`bootstrap_node` must be set to exactly one control plane hostname (used for `talos_machine_bootstrap` and kubeconfig retrieval).

### 3. Bootstrap Cluster

```bash
# Initialize and plan
terraform init
terraform plan

# Apply configuration to bootstrap cluster
terraform apply
```

### 4. Access the Cluster

```bash
# Get Talos client configuration
terraform output -raw talosconfig > ~/.talos/config

# Verify cluster health
talosctl health

# Get Kubernetes configuration
terraform output -raw kubeconfig > ~/.kube/talos-config
export KUBECONFIG=~/.kube/talos-config

# Check cluster status
kubectl get nodes
```

## Adding New Nodes

### 1. Update Networking Configuration

Add the new node to the local-networking configuration:

```hcl
# In local-networking/main.tf
k8s_control_plane_nodes = {
  "c1.k8s.kalski.xyz" = { ... }
  # "c2.k8s.kalski.xyz" = { ip = "10.10.10.12", mac_address = local.config["macs"]["c2_k8s"] }
}

k8s_worker_nodes = {
  "w1.k8s.kalski.xyz" = { ... }
  "w2.k8s.kalski.xyz" = {
    ip          = "10.10.10.22"
    mac_address = local.config["macs"]["w2_k8s"]
  }
}
```

Apply networking changes:

```bash
cd ../local-networking && terraform apply
```

### 2. Boot New Node

Boot the new node with Talos ISO and verify it gets the expected IP.

### 3. Add Node Configuration

Add the new node to `control_plane_node_config` (control plane) or `worker_node_config` (worker) in local-talos:

```hcl
control_plane_node_config = {
  "c1.k8s.kalski.xyz" = { install_disk = "/dev/nvme0n1", install_image = "ghcr.io/talos-rpi5/installer:v1.11.5" }
}

worker_node_config = {
  "w1.k8s.kalski.xyz" = { install_disk = "/dev/nvme0n1", install_image = "ghcr.io/siderolabs/installer:v1.11.5" }
  "w2.k8s.kalski.xyz" = { install_disk = "/dev/sda", install_image = "ghcr.io/siderolabs/installer:v1.11.5" } # Check with talosctl get disks
}
```

### 4. Apply Configuration

```bash
terraform apply
```

The new node will automatically join the existing cluster.

## Storage Configuration

### Current Setup (< 3 workers)

- **local-nvme** StorageClass: Uses disk specified by serial (nvme2n1) for local hostpath storage
- **nvme1n1**: Reserved for future replicated storage
