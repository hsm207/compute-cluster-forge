output "bucket_name" {
  description = "The name of the GCS bucket created for data persistence."
  value       = google_storage_bucket.hpc_storage.name
}

output "project_id" {
  description = "The GCP Project ID."
  value       = var.project_id
}

output "instance_name_prefix" {
  description = "The base name used for GCP instances in the managed instance group."
  value       = var.instance_name_prefix
}
