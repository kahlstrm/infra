variable "a_records" {
  type = map(object({
    ip                = string
    mac_address       = string
    include_subdomain = optional(bool)
  }))
}
