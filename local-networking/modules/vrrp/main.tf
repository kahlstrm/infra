terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
# Creates a physical IP on the specified interface.
resource "routeros_ip_address" "vrrp_physical_ip" {
  count     = var.interface.physical_ip == null ? 0 : 1
  address   = var.interface.physical_ip
  interface = var.interface.name
  comment   = "Terraform: VRRP physical IP"
}

# Creates the VRRP virtual interface.
resource "routeros_interface_vrrp" "vrrp" {
  name            = var.vrrp_name
  interface       = var.interface.name
  priority        = var.priority
  preemption_mode = true
  on_master       = "/ip dhcp-server enable [find name=${var.dhcp_server_name}]"
  on_backup       = "/ip dhcp-server disable [find name=${var.dhcp_server_name}]"
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
  dhcp_server_name = var.dhcp_server_name
  interface_name   = routeros_interface_vrrp.vrrp.name
  network_address  = var.config.vrrp_network
  gateway_ip       = var.config.virtual_ip
  dns_servers      = [var.config.virtual_ip]
  pool_ranges      = var.config.dhcp_pool_ranges
  disabled         = true
}

# currently required for firewall rules to allow connecting to router for DNS
resource "routeros_interface_list_member" "vrrp_lan_list" {
  interface = routeros_interface_vrrp.vrrp.name
  list      = var.lan_interface_list_name
}
