# Configuration for cheap, burst CPU testing (Spike Template)
region         = "us-west1"
machine_type   = "e2-medium"
instance_count = 1
boot_disk_size = 100
boot_disk_type = "pd-balanced"
boot_image     = "click-to-deploy-images/common-cpu-v20250325-debian-11-py310"
allowed_ports  = ["22", "8888"]
