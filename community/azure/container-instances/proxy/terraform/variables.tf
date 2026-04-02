# Azure Container Instances Proxy Variables

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "bytefreezer"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default = {
    Project   = "ByteFreezer"
    ManagedBy = "Terraform"
  }
}

# Container Images
variable "image_registry" {
  description = "Container image registry"
  type        = string
  default     = "ghcr.io/bytefreezer"
}

variable "image_tag" {
  description = "Container image tag"
  type        = string
  default     = "latest"
}

# ByteFreezer Configuration
variable "receiver_url" {
  description = "URL of ByteFreezer receiver"
  type        = string
}

variable "control_service_url" {
  description = "ByteFreezer control service URL"
  type        = string
}

variable "control_service_api_key" {
  description = "API key for control service"
  type        = string
  sensitive   = true
}

# Resource Allocation
variable "cpu" {
  description = "CPU cores"
  type        = number
  default     = 1
}

variable "memory" {
  description = "Memory (GB)"
  type        = number
  default     = 1
}

variable "udp_ports" {
  description = "UDP ports to expose"
  type        = list(number)
  default     = [5514]
}
