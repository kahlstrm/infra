terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.rb5009]
    }
  }
}

module "rb5009" {
  source = "../rb5009"

  providers = {
    routeros = routeros.rb5009
  }

  bootstrap_script   = var.rb5009_config.bootstrap_script
  config             = var.rb5009_config.device_config
  lan_static_leases  = var.rb5009_config.lan_static_leases
  lan_dhcp_config    = var.rb5009_config.lan_dhcp_config
  bridge_interface   = var.rb5009_config.bridge_interface
  dns_a_records      = var.rb5009_config.dns_a_records
  wan_interface      = var.rb5009_config.wan_interface
  stationary_network = var.rb5009_config.stationary_network
  stationary_gateway = var.rb5009_config.stationary_gateway
}
