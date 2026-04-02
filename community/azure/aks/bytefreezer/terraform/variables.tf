# Azure AKS Variables

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

# AKS Configuration
variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.28"
}

variable "node_count" {
  description = "Number of nodes in the default node pool"
  type        = number
  default     = 3
}

variable "node_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "enable_autoscaling" {
  description = "Enable cluster autoscaling"
  type        = bool
  default     = false
}

variable "min_node_count" {
  description = "Minimum number of nodes (when autoscaling enabled)"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes (when autoscaling enabled)"
  type        = number
  default     = 5
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

# Helm Configuration
variable "deploy_helm_chart" {
  description = "Deploy ByteFreezer Helm chart"
  type        = bool
  default     = true
}

variable "helm_chart_path" {
  description = "Path to ByteFreezer Helm chart"
  type        = string
  default     = "../../../helm/bytefreezer"
}

variable "namespace" {
  description = "Kubernetes namespace for ByteFreezer"
  type        = string
  default     = "bytefreezer"
}

# Replica Configuration
variable "receiver_replicas" {
  description = "Number of receiver replicas"
  type        = number
  default     = 2
}

variable "piper_replicas" {
  description = "Number of piper replicas"
  type        = number
  default     = 2
}

variable "packer_replicas" {
  description = "Number of packer replicas"
  type        = number
  default     = 1
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = true
}
