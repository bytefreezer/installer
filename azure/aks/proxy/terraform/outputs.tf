# Azure AKS Proxy Outputs

output "release_name" {
  description = "Helm release name"
  value       = helm_release.proxy.name
}

output "namespace" {
  description = "Kubernetes namespace"
  value       = helm_release.proxy.namespace
}

output "status" {
  description = "Helm release status"
  value       = helm_release.proxy.status
}
