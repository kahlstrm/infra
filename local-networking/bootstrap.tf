locals {
  bootstrap_configs = {
    "hex_s" = {
      system_identity                   = "hex-s"
      local_bridge_name                 = "local-bridge"
      local_bridge_ports                = ["ether2", "ether3", "ether4", "ether5"]
      local_ip_network                  = local.vrrp_shared_config.vrrp_network
      local_bridge_ip_address           = local.vrrp_shared_config.virtual_ip
      secondary_local_bridge_ip_address = local.hex_s.ip
      local_dhcp_server_name            = "vrrp-dhcp"
      local_dhcp_server_lease_time      = "1m" # this is to make clients reconfigure eagerly prior to applying terraform configuration
      local_dhcp_pool_start             = 100
      local_dhcp_pool_end               = 254
      local_dhcp_pool_name              = "vrrp-dhcp"
      shared_lan_interface              = ""
      shared_lan_ip_address_network     = ""
      wan_interface                     = "ether1"
    }
    "rb5009" = {
      system_identity                   = "rb5009"
      local_bridge_name                 = "minirack-bridge"
      local_bridge_ports                = ["ether2", "ether3", "ether4", "ether5", "ether6", "ether7", "sfp-sfpplus1"]
      local_ip_network                  = "10.10.10.0/24"
      local_bridge_ip_address           = "10.10.10.1"
      secondary_local_bridge_ip_address = ""
      local_dhcp_server_name            = "minirack-dhcp"
      local_dhcp_server_lease_time      = "30m"
      local_dhcp_pool_start             = 100
      local_dhcp_pool_end               = 254
      local_dhcp_pool_name              = "minirack-dhcp"
      shared_lan_interface              = "ether1"
      shared_lan_ip_address_network     = "${local.rb5009.ip}/24"
      wan_interface                     = "ether8"
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

data "routeros_files" "hex_s" {
  provider = routeros.hex-s
  filter = {
    name = module.bootstrap_script.hex_s.filename
  }
}

import {
  for_each = data.routeros_files.hex_s.files
  to       = module.hex_s.routeros_file.bootstrap_script
  id       = each.value.id
}

data "routeros_files" "rb5009" {
  provider = routeros.rb5009
  filter = {
    name = module.bootstrap_script.rb5009.filename
  }
}

import {
  for_each = data.routeros_files.rb5009.files
  to       = module.rb5009.routeros_file.bootstrap_script
  id       = each.value.id
}
