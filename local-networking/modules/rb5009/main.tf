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

module "vrrp" {
  source = "../vrrp"
  # The VRRP instance will run on the main LAN bridge, found dynamically.
  interface           = var.config.vrrp_interface
  config              = var.vrrp_shared_config
  priority            = var.config["vrrp_priority"]
  static_leases       = var.vrrp_lan_static_leases
  vrrp_lan_ip_address = "${var.config.shared_lan_ip}/24"
}

module "dhcp_lan" {
  source           = "../dhcp"
  dhcp_server_name = var.lan_dhcp_config.server_name
  interface_name   = var.bridge_interface
  network_address  = var.lan_dhcp_config.network_address
  gateway_ip       = var.config.ip
  dns_servers      = [var.config.ip]
  pool_ranges      = var.lan_dhcp_config.pool_ranges
  static_leases    = var.lan_static_leases
}

module "dns" {
  source     = "../dns"
  a_records  = var.dns_a_records
  use_adlist = true
}

resource "routeros_file" "bootstrap_script" {
  name     = var.bootstrap_script.filename
  contents = var.bootstrap_script.content
}

module "cake" {
  source        = "../cake/"
  down_mbps     = 800
  up_mbps       = 80
  wan_interface = var.wan_interface
  wan_type      = "docsis"
}
