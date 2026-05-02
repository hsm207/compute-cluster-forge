locals {
  feature_ports = {
    "ollama" = ["11434"]
  }

  feature_scripts = [
    for f in var.active_features :
    templatefile("${path.module}/scripts/features/${f}.sh", {
      bucket_name = google_storage_bucket.hpc_storage.name,
      gcp_user    = var.gcp_user
    })
  ]

  final_startup_script = join("\n\n# --- FEATURE LAYER SEPARATOR ---\n\n", concat(
    [templatefile("${path.module}/scripts/startup-script.sh", {
      bucket_name = google_storage_bucket.hpc_storage.name
    })],
    local.feature_scripts
  ))

  total_allowed_ports = distinct(concat(
    var.allowed_ports,
    flatten([for f in var.active_features : lookup(local.feature_ports, f, [])])
  ))
}

# 4. Instance Template for Spot VM Cluster
resource "google_compute_instance_template" "hpc_template" {
  name_prefix  = "hpc-worker-"
  machine_type = var.machine_type
  tags         = [var.instance_tag]

  # Auto-healing and Spot instance pricing (80% savings!)
  scheduling {
    preemptible         = true
    provisioning_model  = "SPOT"
    automatic_restart   = false
    on_host_maintenance = "TERMINATE" # Required for GPUs and Spot VMs
  }

  disk {
    source_image = var.boot_image
    auto_delete  = true
    boot         = true
    disk_size_gb = var.boot_disk_size
    disk_type    = var.boot_disk_type
  }

  network_interface {
    network = "default"
    access_config {
      # Public IP included so VM can download updates for free
    }
  }

  metadata = merge(
    {
      # Secure key management via Google Identity
      enable-oslogin = "TRUE"

      # Declarative software setup via native GCP startup script
      startup-script = local.final_startup_script
    },
    var.gpu_count > 0 ? { "install-nvidia-driver" = "True" } : {}
  )

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

  # Ensure the template is always replaced when startup-script changes
  lifecycle {
    create_before_destroy = true
  }

  # Don't boot the VM until the Gemini API is ready
  depends_on = [google_project_service.gemini_api]
}
