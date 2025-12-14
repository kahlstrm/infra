# hetzner-infra

Terraform layer for Hetzner Cloud resources.

## Bootstrap

1. Authenticate to GCP (Terraform backend + Secret Manager):

   ```bash
   gcloud auth application-default login
   ```

2. Create the Secret Manager secret for this layer:

   ```bash
   terraform init
   terraform apply -target module.secrets
   ```

3. Set the Hetzner API token in the `hetzner-infra` secret:

   ```bash
   just edit
   ```

Use this JSON shape:

```json
{
  "hcloud_token": "..."
}
```

## NixOS infect

Enable nixos-infect via environment variable:

```bash
TF_VAR_ENABLE_NIXOS_INFECT=true terraform apply
```
