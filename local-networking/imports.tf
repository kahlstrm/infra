# One-time adoption of IPv6 objects that the bootstrap script created before
# modules/ipv6 took ownership of them. Only routers provisioned by the old script need
# this; a freshly bootstrapped router has Terraform create them outright.
#
# Remove each block once applied. The .id values are device-specific, so they cannot be
# committed as a general rule - read them from /ipv6/address on the router in question.
#
# kuberack is intentionally absent: it was unreachable at migration time. When it is back,
# add blocks for its DHCPv6 client and its from-pool bridge address.
import {
  to = module.stationary.module.rb5009.module.ipv6.routeros_ipv6_address.lan_from_pool
  id = "*6"
}
