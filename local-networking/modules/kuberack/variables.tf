variable "rb5009_config" {
  type        = any
  description = "RB5009 configuration - see modules/rb5009/variables.tf for schema"
}

variable "external_dns_password" {
  type        = string
  description = "Password for external-dns service account"
  sensitive   = true
}