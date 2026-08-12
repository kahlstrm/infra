variable "config" {
  type = object({
    ip                = string
    transit_address   = string
    transit_interface = string
  })
}

variable "bootstrap_script" {
  type = object({
    filename = string
    content  = string
  })
}


variable "lan_static_leases" {
  type = map(object({
    ip          = string
    mac_address = string
  }))
}

variable "bridge_interface" {
  description = "The name of the main LAN bridge interface."
  type        = string
}

variable "lan_dhcp_config" {
  type = object({
    server_name     = string
    network_address = string
    pool_ranges     = list(string)
  })
}

variable "dns_a_records" {
  type = map(object({
    ip                = string
    include_subdomain = optional(bool)
  }))
}

variable "wan_interface" {
  type = string
}

variable "enable_cake" {
  description = "Enable CAKE QoS on WAN interface"
  type        = bool
  default     = true
}

variable "netwatch_targets" {
  description = "ICMP probe targets for WAN loss/latency monitoring, keyed by probe name. mktxp's netwatch collector is already enabled, so these reach Prometheus without an extra exporter."
  type        = map(string)
  default = {
    cloudflare-dns = "1.1.1.1"
    google-dns     = "8.8.8.8"
  }
}

variable "peers" {
  description = "Peer networks to route to via transit link"
  type = map(object({
    network = string
    gateway = string
  }))
}
