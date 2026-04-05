# 6. Basic Health Check for the managed instance group
resource "google_compute_health_check" "hpc_health" {
  name = "hpc-health-check"

  tcp_health_check {
    port = "22" # Checking SSH connectivity as a proxy for health
  }
}
