# 3. IAP Firewall: ONLY allows Google's IAP Tunnel to reach the VM
resource "google_compute_firewall" "allow_iap" {
  name    = "allow-iap-ssh-web"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = local.total_allowed_ports
  }

  source_ranges = ["35.235.240.0/20"] # Google's IAP range for TCP forwarding
  target_tags   = [var.instance_tag]
}
