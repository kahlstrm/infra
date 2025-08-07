variable "config" {
  type = object({
    ip            = string
    vrrp_priority = number
  })
}

variable "bootstrap_script" {
  type = object({
    filename = string
    content  = string
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

variable "vrrp_interface" {
  description = "name of the interface for the VRRP to be setup on top of"
  type        = string
}

variable "dns_a_records" {
  type = map(object({
    ip                = string
    include_subdomain = optional(bool)
  }))
}
