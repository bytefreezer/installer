# Azure AKS Proxy Variables

variable "resource_group_name" {
  description = "Resource group containing the AKS cluster"
  type        = string
}

variable "aks_cluster_name" {
  description = "Name of existing AKS cluster"
  type        = string
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "bytefreezer-proxy"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "bytefreezer"
}

variable "helm_chart_path" {
  description = "Path to proxy Helm chart"
  type        = string
  default     = "../../../helm/proxy"
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

# Proxy Configuration
variable "replica_count" {
  description = "Number of proxy replicas"
  type        = number
  default     = 1
}

variable "service_type" {
  description = "Kubernetes service type"
  type        = string
  default     = "LoadBalancer"
}

variable "udp_ports" {
  description = "UDP ports to expose"
  type        = list(number)
  default     = [5514]
}
