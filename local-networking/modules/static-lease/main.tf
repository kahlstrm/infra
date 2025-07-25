terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
resource "routeros_ip_dhcp_server_lease" "static_lease" {
  mac_address = var.mac_address
  address     = var.ip_address
  server      = var.dhcp_server
  comment     = var.hostname
}

resource "routeros_dns_record" "dns_record" {
  count           = var.hostname != null ? 1 : 0
  name            = var.hostname
  address         = var.ip_address
  type            = "A"
  match_subdomain = var.include_subdomains
}
