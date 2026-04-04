provider "google" {
  project = var.project_id
  region  = var.region
}

# 1. Random ID suffix for globally unique bucket names
resource "random_id" "suffix" {
  byte_length = 4
}

# 2. Storage Bucket for HPC Data Persistence
resource "google_storage_bucket" "hpc_storage" {
  name          = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
  location      = var.region
  force_destroy = true

  uniform_bucket_level_access = true
}

# 3. IAP Firewall: ONLY allows Google's IAP Tunnel to reach the VM
resource "google_compute_firewall" "allow_iap" {
  name    = "allow-iap-ssh-web"
  network = "default"

  allow {
    protocol = "tcp"
    ports    = ["22", "8080", "8888"]
  }

  source_ranges = ["35.235.240.0/20"] # Google's IAP range for TCP forwarding
  target_tags   = ["hpc-node"]
}

# 4. Instance Template for Spot VM Cluster
resource "google_compute_instance_template" "hpc_template" {
  name_prefix  = "hpc-worker-"
  machine_type = var.machine_type
  tags         = ["hpc-node"]

  # Auto-healing and Spot instance pricing (80% cheaper!)
  scheduling {
    preemptible        = true
    provisioning_model = "SPOT"
    automatic_restart  = false
  }

  disk {
    source_image = var.boot_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size
  }

  network_interface {
    network = "default"
    access_config {
      # Public IP included so VM can download updates for free
    }
  }

  metadata = {
    # Secure key management via Google Identity
    enable-oslogin = "TRUE"

    # Declarative software setup via cloud-init
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      bucket_name = google_storage_bucket.hpc_storage.name
    })
  }

  # GPU attachment if requested
  dynamic "guest_accelerator" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  service_account {
    # Full cloud-platform scope recommended for simplified access to other GCP services
    scopes = ["cloud-platform"]
  }

  # Ensure the template is always replaced when cloud-init changes
  lifecycle {
    create_before_destroy = true
  }
}

# 5. Managed Instance Group for Auto-Healing Cluster Management
resource "google_compute_region_instance_group_manager" "hpc_group" {
  name               = "hpc-manager"
  region             = var.region
  base_instance_name = "hpc-node"
  target_size        = var.instance_count

  version {
    instance_template = google_compute_instance_template.hpc_template.id
  }

  # Ensure the health of the instances in the cluster
  auto_healing_policies {
    health_check      = google_compute_health_check.hpc_health.id
    initial_delay_sec = 300
  }
}

# 6. Basic Health Check for the managed instance group
resource "google_compute_health_check" "hpc_health" {
  name = "hpc-health-check"

  tcp_health_check {
    port = "22" # Checking SSH connectivity as a proxy for health
  }
}
