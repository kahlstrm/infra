locals {
  # Define the shared IPv6 address for the kuberack's connection to the primary LAN

  bootstrap_configs = {
    "stationary_hex_s" = {
      system_identity                = "stationary-hex-s"
      local_bridge_name              = "local-bridge"
      local_bridge_ports             = ["ether3", "ether4", "ether5"]
      local_ipv4_address             = format("%s/24", local.stationary_hex_s.ip)
      local_ipv6_address             = format("%s/64", local.all_router_dns_records[local.stationary_hex_s.domain_name].ipv6)
      all_router_dns_records         = local.all_router_dns_records
      transit_interface              = local.stationary_hex_s.transit_interface
      transit_ipv6_address_network   = "${local.stationary_hex_s.transit_ipv6}/64"
      wan_interface                  = local.stationary_hex_s.wan_interface
      cake_enabled                   = false
      install_zerotier               = true
      management_routes = [
        {
          comment          = "route to RB5009 kuberack for management"
          ipv6_destination = "fd00:de:ad:10::/64"
          ipv6_gateway     = local.kuberack_rb5009.transit_ipv6
          distance         = 255
        }
      ]
    },
    "kuberack_rb5009" = {
      system_identity              = "kuberack-rb5009"
      local_bridge_name            = "kuberack-bridge"
      local_bridge_ports           = ["ether2", "ether3", "ether4", "ether5", "ether6", "ether7", "sfp-sfpplus1"]
      local_ipv4_address           = format("%s/24", local.kuberack_rb5009.ip)
      local_ipv6_address           = format("%s/64", local.all_router_dns_records[local.kuberack_rb5009.domain_name].ipv6)
      all_router_dns_records       = local.all_router_dns_records
      transit_interface            = local.kuberack_rb5009.transit_interface
      transit_ipv6_address_network = "${local.kuberack_rb5009.transit_ipv6}/64"
      wan_interface                = local.kuberack_rb5009.wan_interface
      cake_enabled                 = true
      install_zerotier             = true
      management_routes            = []
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
