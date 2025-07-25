terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

locals {
  vrrp_physical_ip_defined = var.vrrp_interface.physical_ip == null
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
  config             = var.pannu_shared_config
  dhcp_server        = module.vrrp.dhcp_server_name
  include_subdomains = true
}

module "argon_pi_lease" {
  source             = "../static-lease"
  config             = var.argon_pi_shared_config
  dhcp_server        = module.vrrp.dhcp_server_name
  include_subdomains = false
}

module "jetkvm_lease" {
  source             = "../static-lease"
  config             = var.jetkvm_shared_config
  dhcp_server        = module.vrrp.dhcp_server_name
  include_subdomains = false
}

resource "routeros_ip_dns" "dns" {
  allow_remote_requests = true
}

resource "routeros_file" "bootstrap_script" {
  name     = var.config.bootstrap_script_filename
  contents = var.config.bootstrap_script
}
