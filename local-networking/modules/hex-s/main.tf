terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

locals {
  vrrp_physical_ip_defined = var.vrrp_interface.physical_ip == null
  bootstrap_script_path    = "hexS.rsc"
}

provider "routeros" {
  username = var.config.username
  password = var.config.password
  hosturl  = "https://${var.ip}"
  insecure = true
}

moved {
  from = routeros_ip_dhcp_server.bootstrap_dhcp_disable
  to   = module.vrrp.module.dhcp.routeros_ip_dhcp_server.dhcp_server
}

data "routeros_interfaces" "local_bridge_interface" {
  count = local.vrrp_physical_ip_defined ? 0 : 1
  filter = {
    name = var.vrrp_interface.name
  }
}

module "vrrp" {
  source = "../vrrp"
  # The VRRP instance will run on the main LAN bridge, found dynamically.
  interface = {
    name        = local.vrrp_physical_ip_defined ? var.vrrp_interface.name : data.routeros_interfaces.local_bridge_interface[0].interfaces[0].name
    physical_ip = var.vrrp_interface.physical_ip
  }
  dhcp_server_name = "vrrp-dhcp"
  config           = var.vrrp_shared_config
  priority         = 100
}


module "pannu_lease" {
  source             = "../static-lease"
  mac_address        = var.config.pannu_mac_address
  ip_address         = var.pannu_shared_config.ip
  dhcp_server        = module.vrrp.dhcp_server_name
  hostname           = var.pannu_shared_config.dns_hostname
  include_subdomains = true
}

module "argon_pi_lease" {
  source             = "../static-lease"
  mac_address        = var.config.argon_pi_mac_address
  ip_address         = var.argon_pi_shared_config.ip
  dhcp_server        = module.vrrp.dhcp_server_name
  hostname           = var.argon_pi_shared_config.dns_hostname
  include_subdomains = false
}

module "jetkvm_lease" {
  source             = "../static-lease"
  mac_address        = var.config.jetkvm_mac_address
  ip_address         = var.jetkvm_shared_config.ip
  dhcp_server        = module.vrrp.dhcp_server_name
  hostname           = var.jetkvm_shared_config.dns_hostname
  include_subdomains = false
}

resource "routeros_ip_dns" "dns" {
  allow_remote_requests = true
}

resource "routeros_file" "bootstrap_script" {
  name     = local.bootstrap_script_path
  contents = "${var.bootstrap_script}#remove previous bootstrap script so new one can be applied\n/file/remove ${local.bootstrap_script_path}"
}
