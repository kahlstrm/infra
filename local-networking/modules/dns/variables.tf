variable "a_records" {
  type = map(object({
    ip                = string
    include_subdomain = optional(bool)
  }))
}
