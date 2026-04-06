# High-performance training configuration
region         = "us-central1"
machine_type   = "c2-standard-4"
instance_count = 1
boot_disk_size = 100
boot_image     = "debian-cloud/debian-11"
allowed_ports  = ["22", "8888"]
# gpu_type       = "nvidia-tesla-t4" # Uncomment to use GPU
# gpu_count      = 1
