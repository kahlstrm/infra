variable "secret_name" {
  type = string
}
resource "google_secret_manager_secret" "secret" {
  secret_id = var.secret_name
  replication {
    auto {}
  }
  version_destroy_ttl = "86400s"
}
resource "google_secret_manager_secret_version" "secret_version_dummy" {
  secret                 = google_secret_manager_secret.secret.id
  secret_data_wo         = "{\"Do not\":\"Set in Terraform\"}"
  secret_data_wo_version = 1
  lifecycle {
    ignore_changes = [enabled]
  }
}
data "google_secret_manager_secret_version" "secret_version_actual" {
  secret     = google_secret_manager_secret.secret.id
  depends_on = [google_secret_manager_secret_version.secret_version_dummy]
}
output "secret_output_dict" {
  sensitive = true
  value     = jsondecode(data.google_secret_manager_secret_version.secret_version_actual.secret_data)
}
