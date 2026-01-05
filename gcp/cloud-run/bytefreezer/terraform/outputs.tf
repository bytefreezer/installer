# GCP Cloud Run Outputs

output "receiver_url" {
  description = "Receiver service URL"
  value       = google_cloud_run_v2_service.receiver.uri
}

output "piper_url" {
  description = "Piper service URL (internal)"
  value       = google_cloud_run_v2_service.piper.uri
}

output "packer_url" {
  description = "Packer service URL (internal)"
  value       = google_cloud_run_v2_service.packer.uri
}

output "bucket_name" {
  description = "GCS bucket name"
  value       = google_storage_bucket.bytefreezer.name
}

output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.bytefreezer.email
}
