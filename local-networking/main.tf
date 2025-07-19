locals {
  hex_s_peering_ip = "10.254.254.2"
  pannu_shared_config = {
    ip           = "10.1.1.10"
    dns_hostname = "p.kalski.xyz"
  }
  jetkvm_shared_config = {
    ip           = "10.20.10.10"
    dns_hostname = "jetkvm.kalski.xyz"
  }
  argon_pi_shared_config = {
    ip           = "10.1.1.20"
    dns_hostname = "argon.kalski.xyz"
  }
  vrrp_shared_config = {
    vrrp_network = "10.1.1.0/24"
    virtual_ip   = "10.1.1.1"
  }
}

module "hex_s" {
  source                   = "./modules/hex-s"
  ip                       = local.hex_s_peering_ip
  config                   = local.config["hex_s"]
  vrrp_shared_config       = local.vrrp_shared_config
  vrrp_physical_ip         = "10.1.1.3/24"
  pannu_shared_config      = local.pannu_shared_config
  jetkvm_shared_config     = local.jetkvm_shared_config
  argon_pi_shared_config   = local.argon_pi_shared_config
  pannu_physical_interface = "ether3"
  bootstrap_script         = file("${path.root}/bootstrap/hexS.rsc")
}
