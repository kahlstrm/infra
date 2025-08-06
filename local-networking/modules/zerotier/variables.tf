variable "rb5009" {
  type = object({
    internal_ip    = string
    zerotier_ip    = string
    vrrp_interface = string
  })
}

variable "hex_s" {
  type = object({
    internal_ip = string
    zerotier_ip = string
  })
}
