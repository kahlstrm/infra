variable "config" {
  type = object({
    ip                        = string
    bootstrap_script          = string
    bootstrap_script_filename = string
    vrrp_priority             = number
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
  })
}

variable "vrrp_interface" {
  description = "name of the interface for the VRRP to be setup on top of"
  type        = string
}

variable "vrrp_dhcp_server_name" {
  description = "the name of the DHCP server that is setup for the VRRP interface."
  type        = string
}

variable "dns_a_records" {
  type = map(object({
    ip                = string
    mac_address       = string
    include_subdomain = optional(bool)
  }))
}
