# Azure Container Instances Variables

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "bytefreezer"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to all resources"
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
variable "receiver_cpu" {
  description = "CPU cores for receiver"
  type        = number
  default     = 1
}

variable "receiver_memory" {
  description = "Memory (GB) for receiver"
  type        = number
  default     = 1
}

variable "piper_cpu" {
  description = "CPU cores for piper"
  type        = number
  default     = 2
}

variable "piper_memory" {
  description = "Memory (GB) for piper"
  type        = number
  default     = 2
}

variable "packer_cpu" {
  description = "CPU cores for packer"
  type        = number
  default     = 2
}

variable "packer_memory" {
  description = "Memory (GB) for packer"
  type        = number
  default     = 2
}
