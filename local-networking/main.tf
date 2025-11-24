

locals {
  vrrp_shared_config = {
    vrrp_network     = "10.1.1.0/24"
    virtual_ip       = "10.1.1.1"
    dhcp_pool_ranges = ["10.1.1.100-10.1.1.254"]
    dhcp_server_name = "vrrp-dhcp"
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
    "ha.kalski.xyz" = {
      ip          = "10.1.1.20"
      mac_address = local.config["ha_pi_mac_address"]
    }
  }
  k8s_control_plane_nodes = {
    "c1.k8s.kalski.xyz" = {
      ip          = "10.10.10.11"
      mac_address = local.config["c1_k8s_mac_address"]
    }
  }

  k8s_worker_nodes = {
    "w1.k8s.kalski.xyz" = {
      ip          = "10.10.10.21"
      mac_address = local.config["w1_k8s_mac_address"]
    }
  }

  kuberack_lan_static_leases_and_records = merge(
    local.k8s_control_plane_nodes,
    local.k8s_worker_nodes
  )
  stationary_hex_s = {
    ip = "10.1.1.3"
    # TODO: change these when stationary has RB5009 installed
    vrrp_priority = 100
    zerotier_ip   = "10.255.255.2"
    domain_name   = "stationary-hex-s.networking.kalski.xyz"
    wan_interface = "ether1"
  }
  kuberack_rb5009 = {
    shared_lan_ip   = "10.1.1.2"
    shared_lan_ipv6 = "fd00:de:ad:1::2"
    ip              = "10.10.10.1"
    ipv6            = "fd00:de:ad:10::1"
    # TODO: change these when stationary has RB5009 installed
    vrrp_priority  = 254
    vrrp_interface = "ether1"
    zerotier_ip    = "10.255.255.1"
    domain_name    = "kuberack-rb5009.networking.kalski.xyz"
    wan_interface  = "ether8"
  }
  kuberack_network = {
    network = "10.10.10.0/24"
  }
  kuberack_dhcp_config = {
    server_name     = "kuberack-dhcp"
    network_address = "10.10.10.0/24"
    pool_ranges     = ["10.10.10.100-10.10.10.254"]
  }
  all_router_dns_records = {
    "stationary-hex-s.networking.kalski.xyz" = {
      ip   = local.stationary_hex_s.ip
      ipv6 = "fd00:de:ad:1::3"
    },
    "kuberack-rb5009.networking.kalski.xyz" = {
      ip   = local.kuberack_rb5009.ip
      ipv6 = "fd00:de:ad:10::1"
    }
  }
}

locals {
  dns_a_record = merge(local.vrrp_lan_static_leases_and_records, local.kuberack_lan_static_leases_and_records, local.all_router_dns_records)
}


module "stationary" {
  source = "./modules/stationary"
  providers = {
    routeros.hex_s = routeros.stationary_hex_s
  }
  hex_s_config = {
    bootstrap_script         = module.bootstrap_script["stationary_hex_s"]
    device_config            = local.stationary_hex_s
    vrrp_shared_config       = local.vrrp_shared_config
    vrrp_lan_static_leases   = local.vrrp_lan_static_leases_and_records
    bridge_interface         = "local-bridge"
    dns_a_records            = local.dns_a_record
    kuberack_dns_server      = local.kuberack_rb5009.ip
    kuberack_dns_server_ipv6 = local.kuberack_rb5009.ipv6
    kuberack_network         = local.kuberack_network.network
    kuberack_gateway         = local.kuberack_rb5009.shared_lan_ip
  }
}


module "zerotier" {
  source = "./modules/zerotier"
  providers = {
    routeros.stationary = routeros.stationary_hex_s
    routeros.kuberack   = routeros.kuberack_rb5009
    zerotier            = zerotier
  }
  stationary = {
    internal_ip = local.stationary_hex_s.ip
    zerotier_ip = local.stationary_hex_s.zerotier_ip
  }
  kuberack = {
    internal_ip    = local.kuberack_rb5009.ip
    zerotier_ip    = local.kuberack_rb5009.zerotier_ip
    vrrp_interface = local.kuberack_rb5009.vrrp_interface
  }
}

module "mktxp_kuberack" {
  source = "./modules/mktxp-user"
  providers = {
    routeros = routeros.kuberack_rb5009
  }
  username = local.config["mktxp"]["username"]
  password = local.config["mktxp"]["rb5009_password"]
}

module "mktxp_stationary" {
  source = "./modules/mktxp-user"
  providers = {
    routeros = routeros.stationary_hex_s
  }
  username = local.config["mktxp"]["username"]
  password = local.config["mktxp"]["hex_s_password"]
}

module "kuberack" {
  source = "./modules/kuberack"
  providers = {
    routeros.rb5009 = routeros.kuberack_rb5009
  }
  rb5009_config = {
    bootstrap_script       = module.bootstrap_script["kuberack_rb5009"]
    device_config          = local.kuberack_rb5009
    vrrp_shared_config     = local.vrrp_shared_config
    vrrp_lan_static_leases = local.vrrp_lan_static_leases_and_records
    lan_static_leases      = local.kuberack_lan_static_leases_and_records
    lan_dhcp_config        = local.kuberack_dhcp_config
    bridge_interface       = "kuberack-bridge"
    dns_a_records          = local.dns_a_record
    wan_interface          = local.bootstrap_configs.kuberack_rb5009.wan_interface
  }
  external_dns_password = local.config["external_dns_password"]
}

module "stationary_hex_s_cert" {
  source = "./modules/cert"
  providers = {
    routeros = routeros.stationary_hex_s
    acme     = acme
  }
  account_key_pem  = acme_registration.reg.account_key_pem
  cf_dns_api_token = local.config["cf_dns_api_token"]
  domain           = local.stationary_hex_s.domain_name
}

module "kuberack_rb5009_cert" {
  providers = {
    routeros = routeros.kuberack_rb5009
    acme     = acme
  }
  source           = "./modules/cert"
  account_key_pem  = acme_registration.reg.account_key_pem
  cf_dns_api_token = local.config["cf_dns_api_token"]
  domain           = local.kuberack_rb5009.domain_name
}
