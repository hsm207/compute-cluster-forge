# Low-latency inference configuration
region         = "us-central1"
machine_type   = "n2-highcpu-2"
instance_count = 1
boot_disk_size = 100
boot_image     = "debian-cloud/debian-11"
allowed_ports  = ["22", "8888"]
