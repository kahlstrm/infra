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

  bootstrap_script       = var.rb5009_config.bootstrap_script
  config                 = var.rb5009_config.device_config
  lan_static_leases      = var.rb5009_config.lan_static_leases
  lan_dhcp_server_name   = var.rb5009_config.lan_dhcp_server_name
  vrrp_lan_static_leases = var.rb5009_config.vrrp_lan_static_leases
  vrrp_shared_config     = var.rb5009_config.vrrp_shared_config
  dns_a_records          = var.rb5009_config.dns_a_records
  wan_interface          = var.rb5009_config.wan_interface
}