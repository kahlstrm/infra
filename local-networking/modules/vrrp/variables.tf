variable "interface" {
  type = object({
    name        = string
    physical_ip = optional(string)
  })

}
variable "config" {
  type = object({
    vrrp_network     = string
    virtual_ip       = string
    dhcp_pool_ranges = optional(list(string))
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

variable "dhcp_server_name" {
  description = "The name for the failover DHCP server."
  type        = string
}

variable "lan_interface_list_name" {
  description = "Then name for the LAN interface-list"
  type        = string
  default     = "LAN"
}
