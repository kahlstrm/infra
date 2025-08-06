terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}
resource "routeros_ip_dns" "dns" {
  allow_remote_requests = true
  cache_size            = var.use_adlist ? 40960 : 2048
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


resource "routeros_ip_dns_adlist" "stevenblack" {
  count      = var.use_adlist ? 1 : 0
  url        = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
  ssl_verify = false
}

# TODO:
# - DoH? https://help.mikrotik.com/docs/spaces/ROS/pages/37748767/DNS#DNS-dohDNSoverHTTPS(DoH)
