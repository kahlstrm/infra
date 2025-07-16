locals {
  hex_s_ip = "10.20.10.1"
}


module "hex_s" {
  source = "./modules/hex-s"
  ip     = local.hex_s_ip
  config = local.config["hex_s"]
}
