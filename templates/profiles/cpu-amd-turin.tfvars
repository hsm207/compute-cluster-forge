# Next-Gen CPU Layer: AMD Turin (Zen 5) / Intel Emerald Rapids
# Optimized for high-performance CPU inference (100% Hyperdisk required)
machine_type   = "n4d-standard-16"
boot_image      = "click-to-deploy-images/common-cpu-v20250325-debian-11-py310"

# N4D/C4 machines MANDATE Hyperdisk Balanced for boot
boot_disk_type  = "hyperdisk-balanced"
boot_disk_size  = 100
