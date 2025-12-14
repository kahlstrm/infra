terraform {
  required_providers {
    google = {
      version = "~> 6.0"
      source  = "hashicorp/google"
    }
    hcloud = {
      version = "~> 1.0"
      source  = "hetznercloud/hcloud"
    }
  }
}

provider "google" {
  project = "infra-464520"
  region  = "europe-north1"
}

provider "hcloud" {
  token = local.config["hcloud_token"]
}
