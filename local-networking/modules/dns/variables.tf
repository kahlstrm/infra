variable "a_records" {
  type = map(object({
    ip                = string
    include_subdomain = optional(bool)
  }))
}

variable "use_adlist" {
  description = "Enable DNS adlists for blocking ads, trackers, and malicious domains"
  type        = bool
}

variable "additional_dns_servers" {
  description = "Additional DNS servers that are going to be queried first before the others."
  type        = list(string)
  default     = []
}
