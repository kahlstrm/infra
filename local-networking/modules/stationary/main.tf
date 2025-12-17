terraform {
  required_providers {
    routeros = {
      source                = "terraform-routeros/routeros"
      configuration_aliases = [routeros.hex_s]
    }
  }
}

module "hex_s" {
  source = "../hex-s"

  providers = {
    routeros = routeros.hex_s
  }

  bootstrap_script = var.hex_s_config.bootstrap_script
  config           = var.hex_s_config.device_config
  dhcp_config      = var.hex_s_config.dhcp_config
  static_leases    = var.hex_s_config.static_leases
  bridge_interface = var.hex_s_config.bridge_interface
  dns_a_records    = var.hex_s_config.dns_a_records
  kuberack_network = var.hex_s_config.kuberack_network
  kuberack_gateway = var.hex_s_config.kuberack_gateway
}
