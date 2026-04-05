# --- Project Services ---
# Enables the services needed for Gemini CLI
resource "google_project_service" "gemini_api" {
  project = var.project_id
  service = "cloudaicompanion.googleapis.com"

  # Keep it enabled even if we destroy the VM to avoid annoying propagation delays
  disable_on_destroy = false
}
