variable "kuberack" {
  type = object({
    internal_ip    = string
    zerotier_ip    = string
    vrrp_interface = string
  })
}

variable "stationary" {
  type = object({
    internal_ip = string
    zerotier_ip = string
  })
}

variable "poenttoe_ip" {
  type = string
}
