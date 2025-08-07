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

resource "google_secret_manager_secret_version" "initial" {
  secret      = google_secret_manager_secret.secret.id
  secret_data = "{}"

  lifecycle {
    ignore_changes = all
  }
}

data "google_secret_manager_secret_version" "secret_version_actual" {
  secret     = google_secret_manager_secret.secret.id
  depends_on = [google_secret_manager_secret_version.initial]
}
output "secret_output_dict" {
  sensitive = true
  value     = jsondecode(data.google_secret_manager_secret_version.secret_version_actual.secret_data)
}
