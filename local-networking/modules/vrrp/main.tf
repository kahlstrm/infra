terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
# Creates a physical IP on the specified interface.
resource "routeros_ip_address" "vrrp_physical_ip" {
  address   = var.physical_ip
  interface = var.interface_name
  comment   = "Terraform: VRRP physical IP"
}

# Creates the VRRP virtual interface.
resource "routeros_interface_vrrp" "vrrp" {
  name      = var.vrrp_name
  interface = routeros_ip_address.vrrp_physical_ip.interface
  priority  = var.priority
  on_master = "/ip dhcp-server enable [find name=${var.dhcp_server_name}]"
  on_backup = "/ip dhcp-server disable [find name=${var.dhcp_server_name}]"
}

# Creates the virtual IP with a /32 mask and assigns it to the VRRP interface.
resource "routeros_ip_address" "vrrp_virtual_ip" {
  address   = "${var.virtual_ip}/32"
  interface = routeros_interface_vrrp.vrrp.name
  comment   = "Terraform: VRRP virtual IP"
}

# Creates the VRRP DHCP server, bound to the virtual VRRP interface.
resource "routeros_ip_dhcp_server" "vrrp_dhcp_server" {
  name      = var.dhcp_server_name
  interface = routeros_interface_vrrp.vrrp.name
  disabled  = true
  lifecycle {
    ignore_changes = [disabled]
  }
}

resource "routeros_ip_dhcp_server_network" "vrrp_dhcp_server_network" {
  address    = var.dhcp_network_address
  gateway    = var.virtual_ip
  dns_server = [var.virtual_ip]
}

# currently required for firewall rules to allow connecting to router for DNS
resource "routeros_interface_list_member" "vrrp_lan_list" {
  interface = routeros_interface_vrrp.vrrp.name
  list      = var.lan_interface_list_name
}
