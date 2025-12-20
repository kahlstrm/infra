locals {
  bootstrap_configs = {
    "stationary" = {
      system_identity              = "stationary"
      local_bridge_name            = "local-bridge"
      local_bridge_ports           = ["ether2", "ether3", "ether4", "ether5", "ether6", "sfp-sfpplus1"]
      maintenance_port             = "ether7"
      local_ipv4_address           = format("%s/24", local.stationary.ip)
      local_ipv6_address           = format("%s/64", local.stationary.ipv6)
      all_router_dns_records       = local.all_router_dns_records
      transit_interface            = local.stationary.transit_interface
      transit_ipv6_address_network = "${local.stationary.transit_ipv6}/64"
      wan_interface                = local.stationary.wan_interface
      cake_enabled                 = local.stationary.enable_cake
      install_zerotier             = true
      management_routes = [
        {
          comment          = "route to kuberack for management"
          ipv6_destination = format("%s/64", local.kuberack.ipv6)
          ipv6_gateway     = local.kuberack.transit_ipv6
          distance         = 255
        }
      ]
    },
    "kuberack" = {
      system_identity              = "kuberack"
      local_bridge_name            = "kuberack-bridge"
      local_bridge_ports           = ["ether2", "ether3", "ether4", "ether5", "ether6", "ether7", "sfp-sfpplus1"]
      maintenance_port             = ""
      local_ipv4_address           = format("%s/24", local.kuberack.ip)
      local_ipv6_address           = format("%s/64", local.kuberack.ipv6)
      all_router_dns_records       = local.all_router_dns_records
      transit_interface            = local.kuberack.transit_interface
      transit_ipv6_address_network = "${local.kuberack.transit_ipv6}/64"
      wan_interface                = local.kuberack.wan_interface
      cake_enabled                 = local.kuberack.enable_cake
      install_zerotier             = true
      management_routes = [
        {
          comment          = "route to stationary for management"
          ipv6_destination = format("%s/64", local.stationary.ipv6)
          ipv6_gateway     = local.stationary.transit_ipv6
          distance         = 255
        }
      ]
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
  provider = routeros.stationary
  filter = {
    name = module.bootstrap_script.stationary.filename
  }
}

import {
  for_each = data.routeros_files.stationary.files
  to       = module.stationary.module.rb5009.routeros_file.bootstrap_script
  id       = each.value.id
}

data "routeros_files" "kuberack" {
  provider = routeros.kuberack
  filter = {
    name = module.bootstrap_script.kuberack.filename
  }
}

import {
  for_each = data.routeros_files.kuberack.files
  to       = module.kuberack.module.rb5009.routeros_file.bootstrap_script
  id       = each.value.id
}
