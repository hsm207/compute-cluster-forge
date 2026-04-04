output "bucket_name" {
  description = "The name of the GCS bucket created for data persistence."
  value       = google_storage_bucket.hpc_storage.name
}

output "project_id" {
  description = "The GCP Project ID."
  value       = var.project_id
}
