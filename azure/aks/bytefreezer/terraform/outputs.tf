# Azure AKS Outputs

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.bytefreezer.name
}

output "aks_cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.bytefreezer.name
}

output "aks_cluster_id" {
  description = "AKS cluster ID"
  value       = azurerm_kubernetes_cluster.bytefreezer.id
}

output "kube_config" {
  description = "Kubernetes config for kubectl"
  value       = azurerm_kubernetes_cluster.bytefreezer.kube_config_raw
  sensitive   = true
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.bytefreezer.name
}

output "storage_account_endpoint" {
  description = "Storage account blob endpoint"
  value       = azurerm_storage_account.bytefreezer.primary_blob_endpoint
}

output "kubectl_command" {
  description = "Command to configure kubectl"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.bytefreezer.name} --name ${azurerm_kubernetes_cluster.bytefreezer.name}"
}
