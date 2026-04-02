# GCP Cloud Run Proxy Outputs

output "proxy_url" {
  description = "Proxy service URL"
  value       = google_cloud_run_v2_service.proxy.uri
}

output "service_account_email" {
  description = "Service account email"
  value       = google_service_account.proxy.email
}
