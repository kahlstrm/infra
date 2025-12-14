terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.kuberack, routeros.stationary]
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
    servers = [var.kuberack.internal_ip, var.stationary.internal_ip]
  }
  assignment_pool {
    start = "10.255.255.100"
    end   = "10.255.255.254"
  }
  # dynamic "route" {
  #   for_each = [var.kuberack, var.stationary]
  #   content {
  #     target = route.value.internal_ip
  #     via    = route.value.zerotier_ip
  #   }
  # }
}

resource "zerotier_identity" "kuberack" {}

resource "zerotier_member" "kuberack" {
  authorized              = true
  member_id               = zerotier_identity.kuberack.id
  name                    = "kuberack"
  network_id              = zerotier_network.network.id
  hidden                  = false
  allow_ethernet_bridging = true
  no_auto_assign_ips      = true
}

resource "routeros_zerotier" "kuberack_zt1" {
  provider   = routeros.kuberack
  comment    = "ZeroTier Central - Kuberack RB5009"
  identity   = zerotier_identity.kuberack.private_key
  interfaces = ["all"]
  name       = "zt-tunnel"
  port       = 9994
}

resource "routeros_zerotier_interface" "kuberack_zerotier1" {
  provider      = routeros.kuberack
  allow_default = false
  allow_global  = false
  allow_managed = false
  instance      = routeros_zerotier.kuberack_zt1.name
  name          = "zerotier1"
  network       = zerotier_network.network.id
}

resource "routeros_ip_address" "kuberack_zerotier_ip" {
  provider  = routeros.kuberack
  address   = "${var.kuberack.zerotier_ip}/24"
  interface = routeros_zerotier_interface.kuberack_zerotier1.name
}

resource "zerotier_identity" "stationary" {}

resource "zerotier_member" "stationary" {
  authorized              = true
  member_id               = zerotier_identity.stationary.id
  name                    = "stationary"
  network_id              = zerotier_network.network.id
  hidden                  = false
  allow_ethernet_bridging = true
  no_auto_assign_ips      = true
}

resource "routeros_zerotier" "stationary_zt1" {
  provider   = routeros.stationary
  comment    = "ZeroTier Central - Stationary RB5009UGS"
  identity   = zerotier_identity.stationary.private_key
  interfaces = ["all"]
  name       = "zt-tunnel"
  port       = 9994
}

resource "routeros_zerotier_interface" "stationary_zerotier1" {
  provider      = routeros.stationary
  allow_default = false
  allow_global  = false
  allow_managed = false
  instance      = routeros_zerotier.stationary_zt1.name
  name          = "zerotier1"
  network       = zerotier_network.network.id
}

resource "routeros_ip_address" "stationary_zerotier_ip" {
  provider  = routeros.stationary
  address   = "${var.stationary.zerotier_ip}/24"
  interface = routeros_zerotier_interface.stationary_zerotier1.name
}

# Add ZeroTier interfaces to MGMT_ALLOWED list for management access
resource "routeros_interface_list_member" "kuberack_zerotier_mgmt" {
  provider  = routeros.kuberack
  interface = routeros_zerotier_interface.kuberack_zerotier1.name
  list      = "MGMT_ALLOWED"
  comment   = "Allow management via ZeroTier"
}

resource "routeros_interface_list_member" "stationary_zerotier_mgmt" {
  provider  = routeros.stationary
  interface = routeros_zerotier_interface.stationary_zerotier1.name
  list      = "MGMT_ALLOWED"
  comment   = "Allow management via ZeroTier"
}

# Static routes for RB5009
resource "routeros_ip_route" "kuberack_vrrp_lan_fallback" {
  provider      = routeros.kuberack
  dst_address   = "10.1.1.0/24"
  gateway       = var.stationary.zerotier_ip
  distance      = 10
  check_gateway = "ping"
  comment       = "Fallback route to VRRP LAN via ZeroTier"
  depends_on    = [routeros_ip_address.kuberack_zerotier_ip]
}

# Static routes for stationary router
resource "routeros_ip_route" "stationary_kuberack_lan_fallback" {
  provider      = routeros.stationary
  dst_address   = "10.10.10.0/24"
  gateway       = var.kuberack.zerotier_ip
  distance      = 10
  check_gateway = "ping"
  comment       = "Fallback route to Kuberack LAN via ZeroTier"
  depends_on    = [routeros_ip_address.stationary_zerotier_ip]
}

resource "zerotier_identity" "poenttoe" {}

resource "zerotier_member" "poenttoe" {
  authorized              = true
  member_id               = zerotier_identity.poenttoe.id
  name                    = "poenttoe"
  network_id              = zerotier_network.network.id
  hidden                  = false
  allow_ethernet_bridging = true
  no_auto_assign_ips      = true
  ip_assignments          = [var.poenttoe_ip]
}
