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
  interface        = var.vrrp_interface
  dhcp_server_name = var.vrrp_dhcp_server_name
  config           = var.vrrp_shared_config
  priority         = var.config["vrrp_priority"]
  static_leases    = var.vrrp_lan_static_leases
}
module "dns" {
  source    = "../dns"
  a_records = var.dns_a_records
}

resource "routeros_file" "bootstrap_script" {
  name     = var.bootstrap_script.filename
  contents = var.bootstrap_script.content
}
