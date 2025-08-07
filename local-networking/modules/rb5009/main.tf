terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

module "vrrp" {
  source = "../vrrp"
  # The VRRP instance will run on the main LAN bridge, found dynamically.
  interface     = var.config.vrrp_interface
  config        = var.vrrp_shared_config
  priority      = var.config["vrrp_priority"]
  static_leases = var.vrrp_lan_static_leases
}

resource "routeros_ip_dhcp_server_lease" "static_lease" {
  for_each    = var.lan_static_leases
  mac_address = each.value.mac_address
  address     = each.value.ip
  comment     = each.key
  server      = var.lan_dhcp_server_name
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
