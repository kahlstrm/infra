locals {
  pannu_shared_config = {
    ip           = "10.1.1.10"
    dns_hostname = "p.kalski.xyz"
    mac_address  = local.config["pannu_mac_address"]
  }
  jetkvm_shared_config = {
    ip           = "10.1.1.11"
    dns_hostname = "jetkvm.kalski.xyz"
    mac_address  = local.config["jetkvm_mac_address"]
  }
  argon_pi_shared_config = {
    ip           = "10.1.1.20"
    dns_hostname = "argon.kalski.xyz"
    mac_address  = local.config["argon_pi_mac_address"]
  }
  vrrp_shared_config = {
    vrrp_network     = "10.1.1.0/24"
    virtual_ip       = "10.1.1.1"
    dhcp_pool_ranges = ["10.1.1.100-10.1.1.254"]
  }
  hex_s = {
    ip                        = "10.1.1.3"
    bootstrap_script          = file("${path.root}/bootstrap/hexS.rsc")
    bootstrap_script_filename = "hexS.rsc"
  }
}


module "hex_s" {
  source               = "./modules/hex-s"
  config               = local.hex_s
  vrrp_shared_config   = local.vrrp_shared_config
  pannu_shared_config  = local.pannu_shared_config
  jetkvm_shared_config = local.jetkvm_shared_config
  vrrp_interface = {
    name = "local-bridge"
  }
  argon_pi_shared_config = local.argon_pi_shared_config
  providers = {
    routeros = routeros.hex-s
  }
}

# imports the bootstrap dhcp server and network created in the bootstrap-script to state so that we can hijack
# The reason why this works after resetting configuration on device is that terraform lives in a state where:
# - Either the terraform has previously already imported this resource to the state, so it just asks for this specific resource from the router
# - If terraform state does not contain the resources, it will import these.
# Admittedly this is a bit hacky but it works so ¯\_(ツ)_/¯
# NOTE: these IDs rely on the bootstrap script creating the specific things in order, changing the script might break these
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


data "routeros_files" "hexS" {
  provider = routeros.hex-s
  filter = {
    name = local.hex_s.bootstrap_script_filename
  }
}

import {
  for_each = data.routeros_files.hexS.files
  to       = module.hex_s.routeros_file.bootstrap_script
  id       = each.value.id
}
