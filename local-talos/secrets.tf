module "secrets" {
  source      = "../modules/secrets"
  secret_name = "local-talos"
}

locals {
  config = module.secrets.secret_output_dict
}
