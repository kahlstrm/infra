variable "interface" {
  description = "name of the interface where to setup the VRRP on top of."
  type        = string
}

variable "vrrp_lan_ip_address" {
  description = "IP address on the VRRP network"
  type        = string
}

variable "config" {
  type = object({
    vrrp_network     = string
    virtual_ip       = string
    dhcp_pool_ranges = optional(list(string))
    dhcp_server_name = string
  })
}

variable "priority" {
  description = "The VRRP priority for this router (e.g., 255 for master, 100 for backup)."
  type        = number
}

variable "vrrp_name" {
  description = "The name for the VRRP interface."
  type        = string
  default     = "vrrp-lan"
}

variable "static_leases" {
  description = "Static leases for the DHCP server"
  type = map(object({
    ip          = string
    mac_address = string
  }))
}

variable "lan_interface_list_name" {
  description = "Then name for the LAN interface-list"
  type        = string
  default     = "LAN"
}

