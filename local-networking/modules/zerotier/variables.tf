variable "kuberack" {
  type = object({
    internal_ip = string
    zerotier_ip = string
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
