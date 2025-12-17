terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

resource "routeros_ip_address" "bridge_ip" {
  interface = var.bridge_interface
  address   = "${var.config.ip}/24"
}

resource "routeros_ip_address" "transit_address" {
  interface = var.config.transit_interface
  address   = var.config.transit_address
}

module "dhcp_lan" {
  source           = "../dhcp"
  dhcp_server_name = var.dhcp_config.server_name
  interface_name   = var.bridge_interface
  network_address  = var.dhcp_config.network_address
  gateway_ip       = var.config.ip
  dns_servers      = [var.config.ip]
  pool_ranges      = var.dhcp_config.pool_ranges
  static_leases    = var.static_leases
}

module "dns" {
  source     = "../dns"
  a_records  = var.dns_a_records
  use_adlist = true
}

resource "routeros_ip_route" "kuberack_lan_primary" {
  dst_address   = var.kuberack_network
  disabled      = false
  gateway       = var.kuberack_gateway
  check_gateway = "ping"
  distance      = 1
  comment       = "Primary route to Kuberack LAN via wired interconnect"
}

resource "routeros_file" "bootstrap_script" {
  name     = var.bootstrap_script.filename
  contents = var.bootstrap_script.content
}
