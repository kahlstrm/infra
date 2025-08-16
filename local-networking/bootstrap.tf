locals {
  bootstrap_configs = {
    "stationary_hex_s" = {
      system_identity                   = "stationary-hex-s"
      local_bridge_name                 = "local-bridge"
      local_bridge_ports                = ["ether2", "ether3", "ether4", "ether5"]
      local_ip_network                  = local.vrrp_shared_config.vrrp_network
      local_bridge_ip_address           = local.vrrp_shared_config.virtual_ip
      secondary_local_bridge_ip_address = local.stationary_hex_s.ip
      local_dhcp_server_name            = local.vrrp_shared_config.dhcp_server_name
      local_dhcp_server_lease_time      = "1m" # this is to make clients reconfigure eagerly prior to applying terraform configuration
      local_dhcp_pool_start             = 100
      local_dhcp_pool_end               = 254
      local_dhcp_pool_name              = "vrrp-dhcp"
      shared_lan_interface              = ""
      shared_lan_ip_address_network     = ""
      wan_interface                     = "ether1"
      cake_enabled                      = false
      install_zerotier                  = true
      management_routes = [
        {
          destination = "10.10.10.0/24"
          gateway     = local.kuberack_rb5009.shared_lan_ip
          distance    = 255
          comment     = "route to RB5009 kuberack for management"
        }
      ]
    }
    "kuberack_rb5009" = {
      system_identity                   = "kuberack-rb5009"
      local_bridge_name                 = "kuberack-bridge"
      local_bridge_ports                = ["ether2", "ether3", "ether4", "ether5", "ether6", "ether7", "sfp-sfpplus1"]
      local_ip_network                  = "10.10.10.0/24"
      local_bridge_ip_address           = "10.10.10.1"
      secondary_local_bridge_ip_address = ""
      local_dhcp_server_name            = "kuberack-dhcp"
      local_dhcp_server_lease_time      = "30m"
      local_dhcp_pool_start             = 100
      local_dhcp_pool_end               = 254
      local_dhcp_pool_name              = "kuberack-dhcp"
      shared_lan_interface              = "ether1"
      shared_lan_ip_address_network     = "${local.kuberack_rb5009.shared_lan_ip}/24"
      wan_interface                     = "ether8"
      cake_enabled                      = true
      install_zerotier                  = true
      management_routes                 = []
    }
  }
}

module "bootstrap_script" {
  source   = "../modules/templatefile-generator"
  for_each = local.bootstrap_configs
  config = merge(each.value,
    {
      local_bridge_ports = join("; ", formatlist("\"%s\"", each.value.local_bridge_ports))
    }
  )
  filename      = "${each.key}.rsc"
  template_path = "${path.root}/bootstrap/bootstrap.tftpl.rsc"
}

data "routeros_files" "stationary" {
  provider = routeros.stationary_hex_s
  filter = {
    name = module.bootstrap_script.stationary_hex_s.filename
  }
}

import {
  for_each = data.routeros_files.stationary.files
  to       = module.stationary.module.hex_s.routeros_file.bootstrap_script
  id       = each.value.id
}

data "routeros_files" "kuberack" {
  provider = routeros.kuberack_rb5009
  filter = {
    name = module.bootstrap_script.kuberack_rb5009.filename
  }
}

import {
  for_each = data.routeros_files.kuberack.files
  to       = module.kuberack.module.rb5009.routeros_file.bootstrap_script
  id       = each.value.id
}
