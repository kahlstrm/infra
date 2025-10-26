resource "kubernetes_namespace" "traefik" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "traefik"
  }
}

resource "kubernetes_namespace" "external_dns" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "external-dns"
  }
}

resource "kubernetes_secret" "cloudflare_api_token" {
  depends_on = [kubernetes_namespace.traefik]

  metadata {
    name      = "cloudflare-api-token"
    namespace = "traefik"
  }

  data = {
    CF_DNS_API_TOKEN = local.config["cf_dns_api_token"]
  }
}

resource "kubernetes_secret" "mikrotik_credentials" {
  depends_on = [kubernetes_namespace.external_dns]

  metadata {
    name      = "mikrotik-credentials"
    namespace = "external-dns"
  }

  data = {
    MIKROTIK_BASEURL         = "https://${data.terraform_remote_state.networking.outputs.kuberack_domain}"
    MIKROTIK_USERNAME        = data.terraform_remote_state.networking.outputs.external_dns_username
    MIKROTIK_PASSWORD        = local.config["external_dns_password"]
    MIKROTIK_SKIP_TLS_VERIFY = "false"
  }
}
