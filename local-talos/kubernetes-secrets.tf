resource "kubernetes_namespace" "traefik" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "traefik"
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

resource "kubernetes_namespace" "external_dns" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "external-dns"
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
    MIKROTIK_SKIP_TLS_VERIFY = "true"
  }
}

resource "kubernetes_namespace" "monitoring" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "monitoring"
  }
}

resource "kubernetes_secret" "mktxp_config" {
  depends_on = [kubernetes_namespace.monitoring]

  metadata {
    name      = "mktxp-config"
    namespace = "monitoring"
  }

  data = {
    "mktxp.conf" = <<-EOT
      [rb5009]
      hostname = ${data.terraform_remote_state.networking.outputs.kuberack_domain}
      port = 8729
      username = ${local.config["mktxp"]["username"]}
      password = ${local.config["mktxp"]["rb5009_password"]}
      use_ssl = True

      [hexs]
      hostname = ${data.terraform_remote_state.networking.outputs.stationary_domain}
      port = 8729
      username = ${local.config["mktxp"]["username"]}
      password = ${local.config["mktxp"]["hex_s_password"]}
      use_ssl = True
    EOT
  }
}

resource "random_password" "harbor_admin" {
  length  = 32
  special = true
}

resource "kubernetes_namespace" "harbor" {
  depends_on = [talos_cluster_kubeconfig.this]

  metadata {
    name = "harbor"
  }
}

resource "kubernetes_secret" "harbor_admin" {
  depends_on = [kubernetes_namespace.harbor]

  metadata {
    name      = "harbor-admin-password"
    namespace = "harbor"
  }

  data = {
    HARBOR_ADMIN_PASSWORD = random_password.harbor_admin.result
  }
}
