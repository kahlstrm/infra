variable "config" {
  type = object({
    ip             = string
    shared_lan_ip  = string
    vrrp_priority  = number
    vrrp_interface = string
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

variable "vrrp_lan_static_leases" {
  type = map(object({
    ip          = string
    mac_address = string
  }))
}

variable "vrrp_shared_config" {
  type = object({
    vrrp_network     = string
    virtual_ip       = string
    dhcp_pool_ranges = optional(list(string))
    dhcp_server_name = string
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
