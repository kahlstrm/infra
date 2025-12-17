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

variable "stationary_network" {
  description = "The stationary network CIDR (destination for routing)"
  type        = string
}

variable "stationary_gateway" {
  description = "Gateway IP to reach the stationary network via transit link"
  type        = string
}
