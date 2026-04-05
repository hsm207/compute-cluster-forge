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
