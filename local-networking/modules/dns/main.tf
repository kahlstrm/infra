terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
resource "routeros_ip_dns" "dns" {
  allow_remote_requests = true
  servers = [
    "2606:4700:4700::1111",
    "1.1.1.1",
    "2606:4700:4700::1001",
    "1.0.0.1",
  ]
}


resource "routeros_ip_dns_record" "a_record" {
  for_each        = var.a_records
  type            = "A"
  address         = each.value.ip
  match_subdomain = each.value.include_subdomain == true
  name            = each.key
}


# TODO:
# - add adlist configuration https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-adlistAdlist
# - DoH? https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-dohDNSoverHTTPS(DoH)
