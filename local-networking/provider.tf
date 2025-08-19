terraform {
  required_providers {
    google = {
      version = "~> 6.0"
      source  = "hashicorp/google"
    }
    routeros = {
      source  = "terraform-routeros/routeros"
      version = "~> 1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    zerotier = {
      source  = "zerotier/zerotier"
      version = "~> 1.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "~> 2.0"
    }
  }
}

provider "google" {
  project = "infra-464520"
  region  = "europe-north1"
}

variable "ALLOW_INSECURE" {
  default = false
  type    = bool
}

provider "routeros" {
  alias    = "stationary_hex_s"
  hosturl  = "stationary-hex-s.networking.kalski.xyz"
  username = local.config["hex_s"]["username"]
  password = local.config["hex_s"]["password"]
  insecure = var.ALLOW_INSECURE
}

provider "routeros" {
  alias    = "kuberack_rb5009"
  hosturl  = "kuberack-rb5009.networking.kalski.xyz"
  username = local.config["rb5009"]["username"]
  password = local.config["rb5009"]["password"]
  insecure = var.ALLOW_INSECURE
}

provider "zerotier" {
  zerotier_central_token = local.config["zerotier_api_token"]
}

provider "acme" {
  server_url = "https://acme-v02.api.letsencrypt.org/directory"
}

resource "acme_registration" "reg" {
  email_address = "kalle.ahlstrom@iki.fi"
}
