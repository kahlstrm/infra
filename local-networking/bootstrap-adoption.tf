module "bootstrap_adoption" {
  source  = "./modules/bootstrap-adoption"
  configs = local.bootstrap_configs
}

locals {
  bootstrap_adoption = {
    bindings = module.bootstrap_adoption.bindings
    routers = {
      stationary = {
        url      = var.stationary_hosturl
        username = local.config["stationary_rb5009"]["username"]
        password = local.config["stationary_rb5009"]["password"]
        insecure = var.ALLOW_INSECURE
      }
      kuberack = {
        url      = var.kuberack_hosturl
        username = local.config["kuberack_rb5009"]["username"]
        password = local.config["kuberack_rb5009"]["password"]
        insecure = var.ALLOW_INSECURE
      }
    }
  }
}
