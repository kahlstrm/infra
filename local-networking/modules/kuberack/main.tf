terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.kuberack]
    }
  }
}

module "rb5009" {
  source = "../rb5009"

  providers = {
    routeros = routeros.kuberack
  }

  bootstrap_script  = var.config.bootstrap_script
  config            = var.config.device_config
  lan_static_leases = var.config.lan_static_leases
  lan_dhcp_config   = var.config.lan_dhcp_config
  bridge_interface  = var.config.bridge_interface
  dns_a_records     = var.config.dns_a_records
  wan_interface     = var.config.wan_interface
  peers             = var.config.peers
  enable_cake       = var.config.enable_cake
}

resource "routeros_ip_route" "default_via_stationary" {
  provider    = routeros.kuberack
  dst_address = "0.0.0.0/0"
  gateway     = var.config.peers.stationary.gateway
  distance    = 1
  comment     = "Default via stationary"
}
