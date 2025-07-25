terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

# Creates the DHCP server, bound to the specified interface.
resource "routeros_ip_dhcp_server" "dhcp_server" {
  name      = var.dhcp_server_name
  interface = var.interface_name
  disabled  = var.disabled
  lifecycle {
    ignore_changes = [disabled]
  }
}

resource "routeros_ip_dhcp_server_network" "dhcp_server_network" {
  address    = var.network_address
  gateway    = var.gateway_ip
  dns_server = var.dns_servers
}