# GCP GKE Outputs

output "cluster_name" {
  description = "GKE cluster name"
  value       = google_container_cluster.bytefreezer.name
}

output "cluster_endpoint" {
  description = "GKE cluster endpoint"
  value       = google_container_cluster.bytefreezer.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "GKE cluster CA certificate"
  value       = google_container_cluster.bytefreezer.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "bucket_name" {
  description = "GCS bucket name"
  value       = google_storage_bucket.bytefreezer.name
}

output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.bytefreezer.email
}

output "kubectl_command" {
  description = "Command to configure kubectl"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.bytefreezer.name} --region ${var.region} --project ${var.project_id}"
}
