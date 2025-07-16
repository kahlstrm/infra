terraform {
  required_providers {
    routeros = {
      source = "terraform-routeros/routeros"
    }
  }
}

provider "routeros" {
  username = var.config.username
  password = var.config.password
  hosturl  = "https://${var.ip}"
  insecure = true
}

resource "routeros_dns" "dns" {
  allow_remote_requests = true
}
