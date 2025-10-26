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

data "google_secret_manager_secret_version" "bootstrapped" {
  secret            = google_secret_manager_secret.secret.id
  version           = "1"
  fetch_secret_data = false
}

resource "google_secret_manager_secret_version" "initial" {
  count          = can(data.google_secret_manager_secret_version.bootstrapped) ? 0 : 1
  secret         = google_secret_manager_secret.secret.id
  secret_data_wo = "{}"
}

data "google_secret_manager_secret_version" "secret_version_actual" {
  secret = google_secret_manager_secret.secret.id
}

output "secret_output_dict" {
  sensitive = true
  value     = jsondecode(data.google_secret_manager_secret_version.secret_version_actual.secret_data)
}

output "secret_id" {
  description = "The secret ID (name) for use in data sources"
  value       = google_secret_manager_secret.secret.secret_id
}
