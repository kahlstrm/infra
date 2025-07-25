variable "config" {
  type = object({
    ip           = string
    dns_hostname = string
    mac_address  = string
  })
}

variable "dhcp_server" {
  description = "Name of the DHCP server"
  type        = string
}

variable "include_subdomains" {
  description = "Whether to enable matching subdomainds (e.g. foo.example.com hostname will match example.com)"
  type        = bool
}
