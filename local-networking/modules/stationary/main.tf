terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.stationary]
    }
  }
}

module "rb5009" {
  source = "../rb5009"

  providers = {
    routeros = routeros.stationary
  }

  bootstrap_script  = var.config.bootstrap_script
  config            = var.config.device_config
  lan_dhcp_config   = var.config.dhcp_config
  lan_static_leases = var.config.static_leases
  bridge_interface  = var.config.bridge_interface
  dns_a_records     = var.config.dns_a_records
  wan_interface     = var.config.wan_interface
  peers             = var.config.peers
  enable_cake       = var.config.enable_cake
}
