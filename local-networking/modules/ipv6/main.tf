terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

# WAN prefix delegation, and the switch that turns IPv6 off for LAN clients.
#
# Disabling the client drops the delegated prefix, so the from-pool address on the
# bridge loses its global addresses and clients stop being handed routable IPv6.
# The ULA fd00:de:ad::/48 addressing, its AAAA records and the inter-site transit
# routing are unaffected, because those do not come from this pool.
resource "routeros_ipv6_dhcp_client" "wan_pd" {
  interface          = var.wan_interface
  request            = ["prefix"]
  pool_name          = var.pool_name
  pool_prefix_length = 64
  add_default_route  = true
  use_peer_dns       = false
  prefix_hint        = var.prefix_hint
  disabled           = !var.enable_ipv6
  comment            = "terraform: wan prefix delegation"
}
