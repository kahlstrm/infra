terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}


moved {
  from = routeros_ip_dhcp_server.bootstrap_dhcp_disable
  to   = module.vrrp.module.dhcp.routeros_ip_dhcp_server.dhcp_server
}


module "vrrp" {
  source = "../vrrp"
  # The VRRP instance will run on the main LAN bridge, found dynamically.
  interface     = var.vrrp_interface
  config        = var.vrrp_shared_config
  priority      = var.config["vrrp_priority"]
  static_leases = var.vrrp_lan_static_leases
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

