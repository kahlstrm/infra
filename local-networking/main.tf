

locals {
  vrrp_shared_config = {
    vrrp_network     = "10.1.1.0/24"
    virtual_ip       = "10.1.1.1"
    dhcp_pool_ranges = ["10.1.1.100-10.1.1.254"]
  }
  vrrp_lan_static_leases_and_records = {
    "p.kalski.xyz" = {
      ip                = "10.1.1.10"
      mac_address       = local.config["pannu_mac_address"]
      include_subdomain = true
    },
    "jet.kalski.xyz" = {
      ip          = "10.1.1.11"
      mac_address = local.config["jetkvm_mac_address"]
    },
    "unifi.kalski.xyz" = {
      ip          = "10.1.1.20"
      mac_address = local.config["unifi_pi_mac_address"]
    }
  }
  rb5009_lan_static_leases_and_records = {
  }
  configs = {
    hex_s = {
      ip            = "10.1.1.3"
      vrrp_priority = 100
    }
    rb5009 = {
      ip            = "10.1.1.2"
      vrrp_priority = 254
    }
  }
  hex_s = {
    ip            = "10.1.1.3"
    vrrp_priority = 100
  }
  rb5009 = {
    ip            = "10.1.1.2"
    vrrp_priority = 254
  }
  minirack = {
    network = "10.10.10.0/24"
  }
}
locals {
  dns_a_record = merge(local.vrrp_lan_static_leases_and_records, local.rb5009_lan_static_leases_and_records)
}


module "hex_s" {
  source = "./modules/hex-s"
  providers = {
    routeros = routeros.hex-s
  }
  bootstrap_script       = module.bootstrap_script["hex_s"]
  config                 = local.hex_s
  vrrp_shared_config     = local.vrrp_shared_config
  vrrp_lan_static_leases = local.vrrp_lan_static_leases_and_records
  vrrp_interface         = "local-bridge"
  vrrp_dhcp_server_name  = "vrrp-dhcp"
  dns_a_records          = merge(local.vrrp_lan_static_leases_and_records)
}

module "rb5009" {
  source = "./modules/rb5009"
  providers = {
    routeros = routeros.rb5009
  }
  bootstrap_script       = module.bootstrap_script["rb5009"]
  config                 = local.rb5009
  vrrp_shared_config     = local.vrrp_shared_config
  vrrp_lan_static_leases = local.vrrp_lan_static_leases_and_records
  vrrp_interface         = "ether1"
  vrrp_dhcp_server_name  = "vrrp-dhcp"
  dns_a_records          = merge(local.vrrp_lan_static_leases_and_records)
}

# imports the bootstrap dhcp server and network created in the bootstrap-script to state so that we can hijack
# The reason why this works after resetting configuration on device is that terraform lives in a state where:
# - Either the terraform has previously already imported this resource to the state, so it just asks for this specific resource from the router
# - If terraform state does not contain the resources, it will import these.
# Admittedly this is a bit hacky but it works so ¯\_(ツ)_/¯
# NOTE: these IDs rely on the bootstrap script creating the specific things in order, changing the script might break these
# Also, the name of at least the dhcp-server needs to match 1 to 1 in order to avoid rogue DHCP servers. This is due to the fact that
# terraform will create and destroy the old one on name change, that then changes the underlying ID. After ID is changed the import block below
# will be ignored after running "reset configuration" on the device. Next terraform apply will create the dhcp server from scratch, and then you
# end up with 2 competing dhcp servers, one on the VRRP interface and one on the local-bridge interface.
# TL;DR do not change the dhcp server name
import {
  to = module.hex_s.module.vrrp.module.dhcp.routeros_ip_dhcp_server.dhcp_server
  id = "*1"
}
import {
  to = module.hex_s.module.vrrp.module.dhcp.routeros_ip_dhcp_server_network.dhcp_server_network
  id = "*1"
}
import {
  to = module.hex_s.module.vrrp.module.dhcp.routeros_ip_pool.dhcp_pool[0]
  id = "*1"
}
import {
  to = module.hex_s.module.vrrp.routeros_ip_address.vrrp_virtual_ip
  id = "*1"
}

