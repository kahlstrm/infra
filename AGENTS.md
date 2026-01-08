# CLAUDE.md

## Development Environment

```bash
nix develop                              # Enter dev shell (terraform, gcloud, just, talosctl, kubectl)
gcloud auth application-default login    # Authenticate to GCP
```

## Layer Commands

Each infrastructure layer is applied separately in order:

```bash
# Networking layer (MikroTik routers, DHCP, DNS, ZeroTier)
cd local-networking && terraform init && terraform validate && terraform plan && terraform apply

# Talos Kubernetes cluster (depends on local-networking via remote state)
cd local-talos && terraform init && terraform plan && terraform apply

# Hetzner cloud resources
cd hetzner-infra && terraform init && terraform plan && terraform apply
```

Target specific modules: `terraform apply -target=module.stationary` or `terraform apply -target=module.kuberack`

Format all HCL: `terraform fmt -recursive`

## Secret Management

Secrets are stored in Google Secret Manager. Run `just` commands from within the target layer directory:

```bash
just help           # Show available commands
just edit           # Edit secret for current layer (opens $EDITOR)
just view           # View current secret value
just clean --dry-run  # Preview old version cleanup
```

First-time setup for a layer: `terraform apply -target module.secrets` before running `just edit`.

## Architecture

**Layered infrastructure with dependency ordering:**

```
local-networking/     → Network foundation (MikroTik routers, DHCP, DNS, VPN)
    ↓ (remote state)
local-talos/          → Cluster primitives (Talos nodes, ArgoCD, OpenEBS, MetalLB)
    ↓ (GitOps)
local-kubernetes/
  ├── apps-talos/     → Platform services (cert-manager, Traefik, MinIO, Harbor)
  └── apps/           → Portable applications (External-DNS, observability)
```

**local-networking modules:**
- `modules/kuberack/` and `modules/stationary/` - MikroTik router configs for each site
- `modules/rb5009/` - Shared RB5009 router configuration
- `modules/dhcp/`, `modules/dns/`, `modules/cert/` - Network services
- `modules/zerotier/` - VPN site-to-site connectivity
- `bootstrap/` - RouterOS bootstrap templates; `bootstrap/generated/` - generated `.rsc` scripts

**local-talos:** Bootstraps Talos cluster using Siderolabs provider. Consumes networking outputs for node IPs/hostnames.

**Shared modules (`modules/`):**
- `secrets/` - Google Secret Manager wrapper
- `templatefile-generator/` - Template processing utility

## Network Topology

- **Kuberack LAN**: `10.10.10.0/24` / `fd00:de:ad:10::/64` (portable)
- **Stationary LAN**: `10.1.1.0/24` / `fd00:de:ad:1::/64`
- **Transit Link**: `10.254.254.0/30` / `fd00:de:ad:ff::/64` (point-to-point between routers)
- **ZeroTier VPN**: `10.255.255.0/24` (fallback when sites are separated)

## Validation

```bash
terraform validate && terraform plan     # Pre-apply checks
talosctl health                          # Talos cluster health
terraform output -raw kubeconfig > ~/.kube/talos-config && kubectl get nodes
```

Bootstrap script changes regenerate `bootstrap/generated/*.rsc` - review with `git diff` before committing.

## Coding Conventions

- HCL: 2-space indent, `snake_case` for variables/locals
- File layout: `provider.tf`, `backend.tf`, `main.tf`, `outputs.tf`, `secrets.tf`
- Follow existing hostname patterns (e.g., `kuberack-rb5009`, `c1.k8s.kalski.xyz`)
- Commits: short imperative summaries, lowercase (e.g., "add dhcp static lease for pannu")
