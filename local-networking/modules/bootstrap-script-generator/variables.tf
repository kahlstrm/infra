variable "config" {
  description = "A map of configuration values for the bootstrap script."
  type = object({
    system_identity                   = string
    local_bridge_name                 = string
    local_bridge_ports                = list(string)
    local_ip_network                  = string
    local_bridge_ip_address           = string
    secondary_local_bridge_ip_address = string
    local_dhcp_server_name            = string
    local_dhcp_pool_start             = number
    local_dhcp_pool_end               = number
    local_dhcp_pool_name              = string
    shared_lan_interface              = string
    shared_lan_ip_address_network     = string
    wan_interface                     = string
  })
}

variable "template_path" {
  description = "The path to the bootstrap script template file."
  type        = string
}

variable "filename" {
  description = "The filename for the generated file, placed under <template_path_dir>/generated/$filename"
  type        = string
}
