data "hcloud_ssh_key" "mac_personal" {
  name = "mac-personal"
}

resource "hcloud_firewall" "ssh_only" {
  name = "ssh-only"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
}

locals {
  nixos_infect_cloud_config = <<-EOT
    #cloud-config

    runcmd:
      - curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-unstable bash 2>&1 | tee /tmp/infect.log
  EOT
}

resource "hcloud_server" "poenttoe" {
  name        = "poenttoe"
  location    = "hel1"
  server_type = "cpx22"
  image       = "ubuntu-24.04"

  ssh_keys     = [data.hcloud_ssh_key.mac_personal.id]
  firewall_ids = [hcloud_firewall.ssh_only.id]
  user_data    = local.nixos_infect_cloud_config
  lifecycle {
    prevent_destroy = true
  }
}
