# GCP Cloud Run Variables

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
  description = "Prefix for all resource names"
  type        = string
  default     = "bytefreezer"
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project    = "bytefreezer"
    managed-by = "terraform"
  }
}

# Network
variable "network" {
  description = "VPC network name"
  type        = string
  default     = "default"
}

variable "vpc_connector_cidr" {
  description = "CIDR range for VPC connector"
  type        = string
  default     = "10.8.0.0/28"
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

# Storage
variable "force_destroy_bucket" {
  description = "Allow bucket deletion with objects"
  type        = bool
  default     = false
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

# Receiver Configuration
variable "receiver_min_instances" {
  description = "Minimum instances for receiver"
  type        = number
  default     = 0
}

variable "receiver_max_instances" {
  description = "Maximum instances for receiver"
  type        = number
  default     = 10
}

variable "receiver_cpu" {
  description = "CPU for receiver"
  type        = string
  default     = "1"
}

variable "receiver_memory" {
  description = "Memory for receiver"
  type        = string
  default     = "512Mi"
}

variable "receiver_allow_unauthenticated" {
  description = "Allow unauthenticated access to receiver"
  type        = bool
  default     = true
}

# Piper Configuration
variable "piper_min_instances" {
  description = "Minimum instances for piper"
  type        = number
  default     = 1
}

variable "piper_max_instances" {
  description = "Maximum instances for piper"
  type        = number
  default     = 5
}

variable "piper_cpu" {
  description = "CPU for piper"
  type        = string
  default     = "2"
}

variable "piper_memory" {
  description = "Memory for piper"
  type        = string
  default     = "1Gi"
}

# Packer Configuration
variable "packer_min_instances" {
  description = "Minimum instances for packer"
  type        = number
  default     = 1
}

variable "packer_max_instances" {
  description = "Maximum instances for packer"
  type        = number
  default     = 3
}

variable "packer_cpu" {
  description = "CPU for packer"
  type        = string
  default     = "2"
}

variable "packer_memory" {
  description = "Memory for packer"
  type        = string
  default     = "1Gi"
}
