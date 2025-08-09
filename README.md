# Infrastructure

This repository is an experimental playground for managing a personal hardware setup using Infrastructure as Code. It uses Terraform for the declarative setup, Nix for tooling, and Just for scripting, with a focus on leveraging free-tier services from Google Cloud.

## Hardware Setup

### Minirack (Portable)

- [DeskPi RackMate T0](https://deskpi.com/products/deskpi-rackmate-t1-rackmount-10-inch-4u-server-cabinet-for-network-servers-audio-and-video-equipment) - 10" 4U minirack
- [MikroTik RB5009UPr+S+IN](https://mikrotik.com/product/rb5009upr_s_in) - Main router
- [MikroTik CRS310-8G+2S+IN](https://mikrotik.com/product/crs310_8g_2s_in) - Switch
- [Ubiquiti UniFi U7 Pro Wall](https://eu.store.ui.com/eu/en/products/u7-pro-wall) - WiFi access point
- [Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/) - runs a self-hosted Unifi controller for managing the AP
- [Minisforum MS-01](https://minisforumpc.eu/en/products/ms-01) - Compute
- [Zimaboard 2](https://www.zimaspace.com/products/single-board2-server) - Compute

### Stationary Infrastructure

- [MikroTik hEX S (2025)](https://mikrotik.com/product/hex_s_2025) - Secondary router for failover
- pannu - Custom built PC
- [JetKVM](https://jetkvm.com/) - IP KVM for pannu

## Technologies Used

- [Terraform](https://www.terraform.io/)
- [MikroTik RouterOS Terraform provider](https://registry.terraform.io/providers/terraform-routeros/routeros/latest/docs)
- [Google Cloud Platform](https://cloud.google.com/) (GCS, Secret Manager)
- [Nix](https://nixos.org/)
- [Just](https://github.com/casey/just)

## Architecture

This infrastructure uses a **layered approach**:

1. **`local-networking/`** - Network foundation (MikroTik routers, DHCP, DNS)
2. **`local-talos/`** - Talos cluster provisioning (nodes, bootstrap)
3. **`local-kubernetes/`** - Kubernetes workload management _(planned)_

## Getting Started

1. **Setup environment:**

   ```bash
   nix develop
   gcloud auth application-default login
   ```

2. **Deploy in order:**

   ```bash
   # Network layer first
   cd local-networking && terraform init && terraform apply

   # Talos cluster provisioning second
   cd ../local-talos && terraform init && terraform apply
   ```

## Configuration

Secrets are managed using Google Secret Manager. The `modules/secrets` module creates a secret in Secret Manager, but the actual value of the secret must be set manually. This is to avoid storing sensitive information in the repository.

The secret management workflow is designed to stay within the free tier of Google Secret Manager, which allows for up to 6 active secret versions. The provided `just` scripts assist with this; for example, `just clean` will prune old, disabled versions, keeping only the most recent two.

After first running `terraform apply -target module.secrets` inside a layer, you can then go on and setup the required secrets for that layer. To configure the secrets for the `local-networking` layer, you can use the `just edit` command from within the `local-networking` directory. This will open the secret in your default editor (`$EDITOR`, with a fallback to `vim`) and upload the new version to Google Secret Manager.

Alternatively, you can manually create a JSON file with the following structure:

```json
{
  "hex_s": {
    "username": "your-username",
    "password": "your-password"
  }
}
```

Then, you can add this to the `local-networking` secret in Google Secret Manager.
