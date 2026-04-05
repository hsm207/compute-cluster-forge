# GPU Modifier Layer: NVIDIA L4
machine_type  = "g2-standard-4"
boot_image    = "ml-images/common-cu124-debian-11-py310" # CUDA-enabled image
gpu_type      = "nvidia-l4"
gpu_count     = 1
