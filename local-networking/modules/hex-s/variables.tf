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

variable "bridge_interface" {
  description = "name of the interface for the bridge"
  type        = string
}

variable "dns_a_records" {
  type = map(object({
    ip                = string
    include_subdomain = optional(bool)
  }))
}

variable "dhcp_config" {
  type = object({
    server_name     = string
    network_address = string
    pool_ranges     = list(string)
  })
}

variable "static_leases" {
  type = map(object({
    ip          = string
    mac_address = string
  }))
}

variable "kuberack_network" {
  description = "The kuberack network CIDR (destination for routing)"
  type        = string
}

variable "kuberack_gateway" {
  description = "Gateway IP to reach the kuberack network via wired interconnect"
  type        = string
}
