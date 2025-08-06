terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.rb5009, routeros.hex-s]
    }
    zerotier = {
      source = "zerotier/zerotier"
    }
  }
}

resource "zerotier_network" "network" {
  name = "kalski.xyz"
  dns {
    domain  = "kalski.xyz"
    servers = [var.rb5009.internal_ip, var.hex_s.internal_ip]
  }
  assignment_pool {
    start = "10.255.255.100"
    end   = "10.255.255.254"
  }
  # dynamic "route" {
  #   for_each = [var.hex_s, var.rb5009]
  #   content {
  #     target = route.value.internal_ip
  #     via    = route.value.zerotier_ip
  #   }
  # }
}

resource "zerotier_identity" "rb5009" {}

resource "zerotier_member" "rb5009" {
  authorized              = true
  member_id               = zerotier_identity.rb5009.id
  name                    = "rb5009"
  network_id              = zerotier_network.network.id
  hidden                  = false
  allow_ethernet_bridging = true
  no_auto_assign_ips      = true
}

resource "routeros_zerotier" "rb5009_zt1" {
  provider   = routeros.rb5009
  comment    = "ZeroTier Central - RB5009"
  identity   = zerotier_identity.rb5009.private_key
  interfaces = ["all"]
  name       = "zt-tunnel"
  port       = 9994
}

resource "routeros_zerotier_interface" "rb5009_zerotier1" {
  provider      = routeros.rb5009
  allow_default = false
  allow_global  = false
  allow_managed = false
  instance      = routeros_zerotier.rb5009_zt1.name
  name          = "zerotier1"
  network       = zerotier_network.network.id
}

resource "routeros_ip_address" "rb5009_zerotier_ip" {
  provider  = routeros.rb5009
  address   = "${var.rb5009.zerotier_ip}/24"
  interface = routeros_zerotier_interface.rb5009_zerotier1.name
}

resource "zerotier_identity" "hex_s" {}

resource "zerotier_member" "hex_s" {
  authorized              = true
  member_id               = zerotier_identity.hex_s.id
  name                    = "hex_s"
  network_id              = zerotier_network.network.id
  hidden                  = false
  allow_ethernet_bridging = true
  no_auto_assign_ips      = true
}

resource "routeros_zerotier" "hex_s_zt1" {
  provider   = routeros.hex-s
  comment    = "ZeroTier Central - hEX S"
  identity   = zerotier_identity.hex_s.private_key
  interfaces = ["all"]
  name       = "zt-tunnel"
  port       = 9994
}

resource "routeros_zerotier_interface" "hex_s_zerotier1" {
  provider      = routeros.hex-s
  allow_default = false
  allow_global  = false
  allow_managed = false
  instance      = routeros_zerotier.hex_s_zt1.name
  name          = "zerotier1"
  network       = zerotier_network.network.id
}

resource "routeros_ip_address" "hex_s_zerotier_ip" {
  provider  = routeros.hex-s
  address   = "${var.hex_s.zerotier_ip}/24"
  interface = routeros_zerotier_interface.hex_s_zerotier1.name
}

# Add ZeroTier interfaces to MGMT_ALLOWED list for management access
resource "routeros_interface_list_member" "rb5009_zerotier_mgmt" {
  provider  = routeros.rb5009
  interface = routeros_zerotier_interface.rb5009_zerotier1.name
  list      = "MGMT_ALLOWED"
  comment   = "Allow management via ZeroTier"
}

resource "routeros_interface_list_member" "hex_s_zerotier_mgmt" {
  provider  = routeros.hex-s
  interface = routeros_zerotier_interface.hex_s_zerotier1.name
  list      = "MGMT_ALLOWED"
  comment   = "Allow management via ZeroTier"
}

# Static routes for RB5009
resource "routeros_ip_route" "rb5009_vrrp_lan_primary" {
  provider    = routeros.rb5009
  dst_address = "10.1.1.0/24"
  gateway     = var.rb5009.vrrp_interface
  distance    = 1
  comment     = "Primary route to VRRP LAN via physical interface"
}

resource "routeros_ip_route" "rb5009_vrrp_lan_fallback" {
  provider    = routeros.rb5009
  dst_address = "10.1.1.0/24"
  gateway     = var.hex_s.zerotier_ip
  distance    = 10
  comment     = "Fallback route to VRRP LAN via ZeroTier"
  depends_on  = [routeros_ip_address.rb5009_zerotier_ip]
}

# Static routes for hEX S  
resource "routeros_ip_route" "hex_s_minirack_lan_fallback" {
  provider    = routeros.hex-s
  dst_address = "10.10.10.0/24"
  gateway     = var.rb5009.zerotier_ip
  distance    = 10
  comment     = "Fallback route to Minirack LAN via ZeroTier"
  depends_on  = [routeros_ip_address.hex_s_zerotier_ip]
}
