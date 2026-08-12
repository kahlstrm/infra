terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}


resource "routeros_ip_address" "bridge_ip" {
  interface = var.bridge_interface
  address   = "${var.config.ip}/24"
}

resource "routeros_ip_address" "transit_address" {
  interface = var.config.transit_interface
  address   = var.config.transit_address
}

resource "routeros_ip_route" "peer_lan" {
  for_each      = var.peers
  dst_address   = each.value.network
  disabled      = false
  gateway       = each.value.gateway
  check_gateway = "ping"
  distance      = 1
  comment       = "Primary route to ${each.key} LAN via transit link"
}

module "dhcp_lan" {
  source           = "../dhcp"
  dhcp_server_name = var.lan_dhcp_config.server_name
  interface_name   = var.bridge_interface
  network_address  = var.lan_dhcp_config.network_address
  gateway_ip       = var.config.ip
  dns_servers      = [var.config.ip]
  pool_ranges      = var.lan_dhcp_config.pool_ranges
  static_leases    = var.lan_static_leases
}

module "dns" {
  source       = "../dns"
  a_records    = var.dns_a_records
  use_adlist   = true
  use_ipv6_dns = var.enable_ipv6
}

# The ISP's first hop is DHCP-assigned, so read it from the routing table rather than
# pinning a literal that silently rots when the lease changes.
data "routeros_ip_routes" "default" {
  filter = {
    dst_address = "0.0.0.0/0"
  }
}

module "netwatch" {
  source = "../netwatch"
  targets = merge(
    var.netwatch_targets,
    try({ "isp-gateway" = data.routeros_ip_routes.default.routes[0].gateway }, {}),
  )
}

module "ipv6" {
  source           = "../ipv6"
  wan_interface    = var.wan_interface
  bridge_interface = var.bridge_interface
  enable_ipv6      = var.enable_ipv6
  prefix_hint      = var.ipv6_prefix_hint
}

resource "routeros_file" "bootstrap_script" {
  name     = var.bootstrap_script.filename
  contents = var.bootstrap_script.content
}

module "cake" {
  count         = var.enable_cake ? 1 : 0
  source        = "../cake/"
  down_mbps     = 800
  up_mbps       = 80
  wan_interface = var.wan_interface
  wan_type      = "docsis"
}
