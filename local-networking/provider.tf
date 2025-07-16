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
  }
}

provider "google" {
  project = "infra-464520"
  region  = "europe-north1"
}

