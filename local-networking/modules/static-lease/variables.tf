variable "mac_address" {
  description = "MAC address for the static lease"
  type        = string
}

variable "ip_address" {
  description = "IP address for the static lease"
  type        = string
}

variable "dhcp_server" {
  description = "Name of the DHCP server"
  type        = string
}

variable "hostname" {
  description = "Hostnames for the DNS record"
  type        = string
}

variable "include_subdomains" {
  description = "Whether to enable matching subdomainds (e.g. foo.example.com hostname will match example.com)"
  type        = bool
}
