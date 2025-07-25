terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
resource "routeros_ip_dhcp_server_lease" "static_lease" {
  mac_address = var.config.mac_address
  address     = var.config.ip
  server      = var.dhcp_server
  comment     = var.config.dns_hostname
}

resource "routeros_dns_record" "dns_record" {
  count           = var.config.dns_hostname != null ? 1 : 0
  name            = var.config.dns_hostname
  address         = var.config.ip
  type            = "A"
  match_subdomain = var.include_subdomains
}
