terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
    acme = {
      source = "vancluever/acme"
    }
  }
}


resource "acme_certificate" "cert" {
  account_key_pem = var.account_key_pem
  common_name     = var.domain

  dns_challenge {
    provider = "cloudflare"
    config = {
      CF_DNS_API_TOKEN = var.cf_dns_api_token
    }
  }
}

resource "routeros_system_certificate" "external" {
  name        = "${acme_certificate.cert.common_name}.crt"
  common_name = acme_certificate.cert.common_name
  import {
    cert_file_content = acme_certificate.cert.certificate_pem
    key_file_content  = acme_certificate.cert.private_key_pem
  }
}

resource "routeros_system_certificate" "external_issuer" {
  name        = "${acme_certificate.cert.common_name}.issuer.crt"
  common_name = "issuer"
  import {
    cert_file_content = acme_certificate.cert.issuer_pem
  }
  lifecycle {
    ignore_changes = [common_name]
  }
}

# Enable HTTPS WebFig with that cert; disable plain HTTP
resource "routeros_ip_service" "www" {
  numbers  = "www"
  port     = 80
  disabled = true
}

resource "routeros_ip_service" "api_ssl" {
  numbers     = "api-ssl"
  certificate = routeros_system_certificate.external.name
  port        = 8729
  disabled    = false
}

resource "routeros_ip_service" "www_ssl" {
  numbers     = "www-ssl"
  certificate = routeros_system_certificate.external.name
  port        = 443
  disabled    = false
}
