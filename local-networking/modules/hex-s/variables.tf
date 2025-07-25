variable "config" {
  type = object({
    ip                        = string
    bootstrap_script          = string
    bootstrap_script_filename = string
  })
}

variable "pannu_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
    mac_address  = string
  })
}

variable "jetkvm_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
    mac_address  = string
  })
}

variable "argon_pi_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
    mac_address  = string
  })
}

variable "vrrp_shared_config" {
  type = object({
    vrrp_network     = string
    virtual_ip       = string
    dhcp_pool_ranges = optional(list(string))
  })
}

variable "vrrp_interface" {
  type = object({
    name        = string
    physical_ip = optional(string)
  })
}

variable "vrrp_dhcp_server_name" {
  description = "the name of the DHCP server that is setup for the VRRP interface. Must match the bootstrap script on the hEX S"
  type        = string
}
