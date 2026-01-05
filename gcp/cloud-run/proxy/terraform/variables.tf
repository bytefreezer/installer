# GCP Cloud Run Proxy Variables

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "bytefreezer"
}

variable "labels" {
  description = "Labels to apply to resources"
  type        = map(string)
  default = {
    project    = "bytefreezer"
    managed-by = "terraform"
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

# Scaling Configuration
variable "min_instances" {
  description = "Minimum instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum instances"
  type        = number
  default     = 5
}

variable "cpu" {
  description = "CPU allocation"
  type        = string
  default     = "1"
}

variable "memory" {
  description = "Memory allocation"
  type        = string
  default     = "512Mi"
}

variable "allow_unauthenticated" {
  description = "Allow unauthenticated access"
  type        = bool
  default     = true
}
