terraform {
  required_providers {
    google = {
      version = "~> 6.0"
      source  = "hashicorp/google"
    }
    talos = {
      version = "0.9.0-alpha.0"
      source  = "siderolabs/talos"
    }
  }
}

provider "google" {
  project = "infra-464520"
  region  = "europe-north1"
}

provider "talos" {}
