output "dhcp_server_name" {
  description = "The name of the created VRRP DHCP server."
  value       = routeros_ip_dhcp_server.vrrp_dhcp_server.name
}

output "vrrp_interface_name" {
  description = "The name of the created VRRP interface."
  value       = routeros_interface_vrrp.vrrp.name
}
