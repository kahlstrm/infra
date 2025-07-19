terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

provider "routeros" {
  username = var.config.username
  password = var.config.password
  hosturl  = "https://${var.ip}"
  insecure = true
}

module "vrrp" {
  source               = "../vrrp"
  interface_name       = var.pannu_physical_interface
  physical_ip          = var.vrrp_physical_ip
  virtual_ip           = var.vrrp_shared_config.virtual_ip
  dhcp_network_address = var.vrrp_shared_config.vrrp_network
  priority             = 100
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
  dhcp_server        = "local-bridge"
  hostname           = var.jetkvm_shared_config.dns_hostname
  include_subdomains = false
}

resource "routeros_ip_dns" "dns" {
  allow_remote_requests = true
}

resource "routeros_file" "test" {
  name     = "hexS.rsc"
  contents = var.bootstrap_script
}
