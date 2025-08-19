terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

resource "routeros_ip_address" "shared_lan_ip" {
  interface = var.interface
  address   = var.vrrp_lan_ip_address
}

# Creates the VRRP virtual interface.
resource "routeros_interface_vrrp" "vrrp" {
  name            = var.vrrp_name
  interface       = var.interface
  priority        = var.priority
  preemption_mode = true
  # do this to clean the lease table on backup
  on_master = "/ip dhcp-server enable [find name=${var.config.dhcp_server_name}]"
  on_backup = "/ip dhcp-server disable [find name=${var.config.dhcp_server_name}]"
}

# Creates the virtual IP with a /32 mask and assigns it to the VRRP interface.
resource "routeros_ip_address" "vrrp_virtual_ip" {
  address   = "${var.config.virtual_ip}/32"
  interface = routeros_interface_vrrp.vrrp.name
  comment   = "Terraform: VRRP virtual IP"
}

# Creates the DHCP server using the dedicated DHCP module
module "dhcp" {
  source           = "../dhcp"
  dhcp_server_name = var.config.dhcp_server_name
  interface_name   = routeros_interface_vrrp.vrrp.name
  network_address  = var.config.vrrp_network
  gateway_ip       = var.config.virtual_ip
  dns_servers      = [var.config.virtual_ip]
  pool_ranges      = var.config.dhcp_pool_ranges
  static_leases    = var.static_leases
}

# currently required for firewall rules to allow connecting to router for DNS
resource "routeros_interface_list_member" "vrrp_lan_list" {
  interface = routeros_interface_vrrp.vrrp.name
  list      = var.lan_interface_list_name
}
