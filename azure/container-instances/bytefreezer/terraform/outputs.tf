# Azure Container Instances Outputs

output "resource_group_name" {
  description = "Resource group name"
  value       = azurerm_resource_group.bytefreezer.name
}

output "receiver_fqdn" {
  description = "Receiver public FQDN"
  value       = azurerm_container_group.receiver.fqdn
}

output "receiver_ip" {
  description = "Receiver public IP"
  value       = azurerm_container_group.receiver.ip_address
}

output "receiver_url" {
  description = "Receiver webhook URL"
  value       = "http://${azurerm_container_group.receiver.fqdn}:8080"
}

output "storage_account_name" {
  description = "Storage account name"
  value       = azurerm_storage_account.bytefreezer.name
}
