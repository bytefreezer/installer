# Azure Container Instances Proxy Outputs

output "proxy_fqdn" {
  description = "Proxy public FQDN"
  value       = azurerm_container_group.proxy.fqdn
}

output "proxy_ip" {
  description = "Proxy public IP"
  value       = azurerm_container_group.proxy.ip_address
}

output "api_url" {
  description = "Proxy API URL"
  value       = "http://${azurerm_container_group.proxy.fqdn}:8008"
}
