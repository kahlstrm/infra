variable "config" {
  type = object({
    username             = string
    password             = string
    pannu_mac_address    = string
    jetkvm_mac_address   = string
    argon_pi_mac_address = string
  })
}

variable "ip" {
  description = "ip of the device"
  type        = string
}

variable "pannu_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
  })
}

variable "jetkvm_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
  })
}

variable "argon_pi_shared_config" {
  type = object({
    ip           = string
    dns_hostname = string
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

variable "bootstrap_script" {
  description = "Contents for the bootstrap script used with reset configuration"
  type        = string
}

