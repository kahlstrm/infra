variable "dhcp_server_name" {
  description = "The name for the DHCP server."
  type        = string
}

variable "interface_name" {
  description = "The interface to bind the DHCP server to."
  type        = string
}

variable "network_address" {
  description = "The network address for the DHCP server."
  type        = string
}

variable "gateway_ip" {
  description = "The gateway IP address for DHCP clients."
  type        = string
}

variable "dns_servers" {
  description = "List of DNS server IP addresses."
  type        = list(string)
}

variable "disabled" {
  description = "Whether the DHCP server should be disabled initially."
  type        = bool
  default     = false
}