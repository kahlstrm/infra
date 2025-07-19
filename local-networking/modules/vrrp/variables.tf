variable "interface_name" {
  description = "The physical interface to run VRRP on."
  type        = string
}

variable "physical_ip" {
  description = "The physical IP address (CIDR) for the VRRP interface."
  type        = string
}

variable "virtual_ip" {
  description = "The virtual IP address (CIDR with /32 mask) for the VRRP group."
  type        = string
}

variable "dhcp_network_address" {
  description = "The network for the DHCP server."
  type        = string
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
  default     = "vrrp-dhcp-server"
}

variable "lan_interface_list_name" {
  description = "Then name for the LAN interface-list"
  type        = string
  default     = "LAN"
}
