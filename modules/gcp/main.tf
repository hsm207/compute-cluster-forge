provider "google" {
  project = var.project_id
  region  = var.region
}

# --- Dynamic Hardware Discovery ---
data "google_compute_zones" "available" {
  region  = var.region
  project = var.project_id
}

data "google_compute_machine_types" "available" {
  for_each = toset(data.google_compute_zones.available.names)
  zone     = each.key
  project  = var.project_id
  filter   = "name = \"${var.machine_type}\""
}

locals {
  supported_zones = [
    for z in data.google_compute_zones.available.names :
    z if length(data.google_compute_machine_types.available[z].machine_types) > 0
  ]
}
