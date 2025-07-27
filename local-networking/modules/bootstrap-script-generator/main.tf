locals {
  content = templatefile(var.template_path, merge(
    var.config,
    {
      local_bridge_ports = join("; ", formatlist("\"%s\"", var.config.local_bridge_ports))
    }
  ))
}
resource "local_file" "bootstrap_script" {
  content  = local.content
  filename = "${dirname(var.template_path)}/generated/${var.filename}"
}
