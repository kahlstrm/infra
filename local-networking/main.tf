

locals {
  stationary_lan = {
    network          = "10.1.1.0/24"
    gateway_ip       = "10.1.1.1"
    dhcp_pool_ranges = ["10.1.1.100-10.1.1.254"]
    dhcp_server_name = "stationary-dhcp"
  }
  stationary_lan_static_leases_and_records = {
    "p.kalski.xyz" = {
      ip                = "10.1.1.10"
      mac_address       = local.config["macs"]["pannu"]
      include_subdomain = true
    },
    "jet.kalski.xyz" = {
      ip          = "10.1.1.11"
      mac_address = local.config["macs"]["jetkvm"]
    },
    "ha.kalski.xyz" = {
      ip          = "10.1.1.20"
      mac_address = local.config["macs"]["ha_pi"]
    }
    "zima.kalski.xyz" = {
      ip                = "10.1.1.30"
      mac_address       = local.config["macs"]["zima"]
      include_subdomain = true
    }
  }
  external_dns_records = {
    "poenttoe.kalski.xyz" = {
      ip = "10.255.255.3"
    }
  }
  k8s_control_plane_nodes = {
    "c1.k8s.kalski.xyz" = {
      ip          = "10.10.10.11"
      mac_address = local.config["macs"]["c1_k8s"]
    }
    "c2.k8s.kalski.xyz" = {
      ip          = "10.10.10.12"
      mac_address = local.config["macs"]["c2_k8s"]
    }
    "c3.k8s.kalski.xyz" = {
      ip          = "10.10.10.13"
      mac_address = local.config["macs"]["c3_k8s"]
    }
  }

  k8s_worker_nodes = {
    "w1.k8s.kalski.xyz" = {
      ip          = "10.10.10.21"
      mac_address = local.config["macs"]["w1_k8s"]
    }
  }

  kuberack_lan_static_leases_and_records = merge(
    local.k8s_control_plane_nodes,
    local.k8s_worker_nodes, {
      "jet.k8s.kalski.xyz" = {
        ip          = "10.10.10.5"
        mac_address = local.config["macs"]["kuberack_jetkvm"]
      }
    }
  )
  transit_network = {
    kuberack_address     = "10.254.254.1/30"
    stationary_address   = "10.254.254.2/30"
    kuberack_ipv6        = "fd00:de:ad:ff::1"
    stationary_ipv6      = "fd00:de:ad:ff::2"
    stationary_interface = "ether2"
  }
  stationary_hex_s = {
    ip                = local.stationary_lan.gateway_ip
    zerotier_ip       = "10.255.255.2"
    domain_name       = "stationary-hex-s.networking.kalski.xyz"
    wan_interface     = "ether1"
    transit_address   = local.transit_network.stationary_address
    transit_ipv6      = local.transit_network.stationary_ipv6
    transit_interface = local.transit_network.stationary_interface
  }
  kuberack_rb5009 = {
    transit_address   = local.transit_network.kuberack_address
    transit_ipv6      = local.transit_network.kuberack_ipv6
    transit_interface = "ether1"
    ip                   = "10.10.10.1"
    ipv6                 = "fd00:de:ad:10::1"
    zerotier_ip          = "10.255.255.1"
    domain_name          = "kuberack-rb5009.networking.kalski.xyz"
    wan_interface        = "ether8"
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
  dns_a_record = merge(local.stationary_lan_static_leases_and_records, local.kuberack_lan_static_leases_and_records, local.all_router_dns_records, local.external_dns_records)
}


module "stationary" {
  source = "./modules/stationary"
  providers = {
    routeros.hex_s = routeros.stationary_hex_s
  }
  hex_s_config = {
    bootstrap_script = module.bootstrap_script["stationary_hex_s"]
    device_config    = local.stationary_hex_s
    dhcp_config = {
      server_name     = local.stationary_lan.dhcp_server_name
      network_address = local.stationary_lan.network
      pool_ranges     = local.stationary_lan.dhcp_pool_ranges
    }
    static_leases    = local.stationary_lan_static_leases_and_records
    bridge_interface = "local-bridge"
    dns_a_records    = local.dns_a_record
    kuberack_network = local.kuberack_network.network
    kuberack_gateway = split("/", local.kuberack_rb5009.transit_address)[0]
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
    internal_ip = local.kuberack_rb5009.ip
    zerotier_ip = local.kuberack_rb5009.zerotier_ip
  }
  poenttoe_ip = local.external_dns_records["poenttoe.kalski.xyz"].ip
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

module "external_dns_kuberack" {
  source = "./modules/external-dns-user"
  providers = {
    routeros = routeros.kuberack_rb5009
  }
  external_dns_password = local.config["external_dns_password"]
}

module "external_dns_hex_s" {
  source = "./modules/external-dns-user"
  providers = {
    routeros = routeros.stationary_hex_s
  }
  external_dns_password = local.config["external_dns_password"]
}

module "kuberack" {
  source = "./modules/kuberack"
  providers = {
    routeros.rb5009 = routeros.kuberack_rb5009
  }
  rb5009_config = {
    bootstrap_script   = module.bootstrap_script["kuberack_rb5009"]
    device_config      = local.kuberack_rb5009
    lan_static_leases  = local.kuberack_lan_static_leases_and_records
    lan_dhcp_config    = local.kuberack_dhcp_config
    bridge_interface   = "kuberack-bridge"
    dns_a_records      = local.dns_a_record
    wan_interface      = local.bootstrap_configs.kuberack_rb5009.wan_interface
    stationary_network = local.stationary_lan.network
    stationary_gateway = split("/", local.stationary_hex_s.transit_address)[0]
  }
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

resource "routeros_system_user_sshkeys" "admin_keys_stationary" {
  provider = routeros.stationary_hex_s
  for_each = nonsensitive(local.config["ssh_public_keys"])
  user     = local.config["hex_s"]["username"]
  key      = each.value
  comment  = each.key
}

resource "routeros_system_user_sshkeys" "admin_keys_kuberack" {
  provider = routeros.kuberack_rb5009
  for_each = nonsensitive(local.config["ssh_public_keys"])
  user     = local.config["rb5009"]["username"]
  key      = each.value
  comment  = each.key
}
