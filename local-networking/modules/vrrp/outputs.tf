output "dhcp_server_name" {
  description = "The name of the created VRRP DHCP server."
  value       = module.dhcp.dhcp_server_name
}

output "vrrp_interface_name" {
  description = "The name of the created VRRP interface."
  value       = routeros_interface_vrrp.vrrp.name
}
