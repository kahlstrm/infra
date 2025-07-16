variable "config" {
  type = object({
    username = string
    password = string
  })
}

variable "ip" {
  description = "ip of the device"
  type        = string
}
