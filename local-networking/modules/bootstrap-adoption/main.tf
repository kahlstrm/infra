variable "configs" {
  description = "The same site configurations used to render bootstrap scripts."
  type        = any
}

locals {
  bindings = flatten([
    for site, config in var.configs : [for binding in concat(
      [
        {
          address = "module.${site}.module.rb5009.routeros_ip_address.bridge_ip"
          path    = "ip/address"
          match   = { address = config.local_ipv4_address, interface = config.local_bridge_name }
        },
        {
          address = "module.${site}.module.rb5009.routeros_ip_address.transit_address"
          path    = "ip/address"
          match   = { address = config.transit_ipv4_address, interface = config.transit_interface }
        },
        {
          address  = "module.${site}.module.rb5009.routeros_file.bootstrap_script"
          path     = "file"
          match    = { name = "${site}.rsc" }
          optional = true
        }
      ],
      [for peer, other in var.configs : {
        address = "module.${site}.module.rb5009.routeros_ip_route.peer_lan[${jsonencode(peer)}]"
        path    = "ip/route"
        match = {
          dst-address = cidrsubnet(other.local_ipv4_address, 0, 0)
          gateway     = split("/", other.transit_ipv4_address)[0]
        }
      } if peer != site],
      flatten([for name, record in config.all_router_dns_records : [
        {
          address = "module.${site}.module.rb5009.module.dns.routeros_ip_dns_record.a_record[${jsonencode(name)}]"
          path    = "ip/dns/static"
          match   = { name = name, type = "A", address = record.ip }
        }
      ]])
    ) : merge(binding, { router = site })]
  ])
}

output "bindings" {
  value = local.bindings
}
