variable "wan_interface" {
  description = "WAN interface the DHCPv6-PD client runs on."
  type        = string
}

variable "enable_ipv6" {
  description = "Request a prefix from the ISP. Set false to stop handing routable IPv6 to LAN clients while upstream IPv6 is broken; ULA addressing and inter-site routing are unaffected."
  type        = bool
}

variable "pool_name" {
  description = "IPv6 pool the delegated prefix is written into. Must match the pool the bridge address takes its prefix from."
  type        = string
  default     = "wan-ipv6-pool"
}

variable "prefix_hint" {
  description = "Prefix size to request from the ISP, e.g. \"::/56\". DNA documents a /56 with a prefix hint. Null omits the hint."
  type        = string
  default     = null
}
