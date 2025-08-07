data "terraform_remote_state" "networking" {
  backend = "gcs"
  config = {
    bucket = "terraform-state-1751317459"
    prefix = "local-networking"
  }
}

locals {
  networking = data.terraform_remote_state.networking.outputs
}
