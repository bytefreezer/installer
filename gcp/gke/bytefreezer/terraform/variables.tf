# GCP GKE Variables

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone (leave empty for regional cluster)"
  type        = string
  default     = ""
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

variable "subnetwork" {
  description = "VPC subnetwork name"
  type        = string
  default     = "default"
}

# GKE Configuration
variable "node_count" {
  description = "Number of nodes per zone"
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "Minimum nodes for autoscaling"
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes for autoscaling"
  type        = number
  default     = 5
}

variable "machine_type" {
  description = "GCE machine type for nodes"
  type        = string
  default     = "e2-standard-2"
}

variable "disk_size_gb" {
  description = "Disk size for nodes"
  type        = number
  default     = 50
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
  description = "Kubernetes namespace"
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
