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

Edit `main.tf` and update the `node_config` local with the correct disk paths:

```hcl
node_config = {
  "c1.k8s.kalski.xyz" = {
    talos_install_disk = "/dev/mmcblk0"
  }
  "w1.k8s.kalski.xyz" = {
    talos_install_disk = "/dev/nvme1n1"
  }
}
```

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
k8s_worker_nodes = {
  "w1.k8s.kalski.xyz" = { ... }
  "w2.k8s.kalski.xyz" = {
    ip          = "10.10.10.22"
    mac_address = local.config["w2_k8s_mac_address"]
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

Add the new node to `node_config` in local-talos:

```hcl
node_config = {
  "c1.k8s.kalski.xyz" = { talos_install_disk = "/dev/mmcblk0" }
  "w1.k8s.kalski.xyz" = { talos_install_disk = "/dev/nvme1n1" }
  "w2.k8s.kalski.xyz" = { talos_install_disk = "/dev/sda" }  # Check with talosctl get disks
}
```

### 4. Apply Configuration

```bash
terraform apply
```

The new node will automatically join the existing cluster.

## Troubleshooting

- **Nodes not accessible**: Verify network connectivity and DHCP assignments
- **Configuration apply fails**: Check disk paths exist and nodes are responsive
- **Bootstrap hangs**: Control plane initialization can take several minutes
