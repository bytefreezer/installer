variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "site_name" {
  description = "Name for this proxy site (e.g., us-east, datacenter-1)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks (minimum 2 for NLB)"
  type        = list(string)
}

variable "image_tag" {
  description = "Docker image tag for ByteFreezer proxy"
  type        = string
  default     = "latest"
}

variable "image_registry" {
  description = "Docker image registry"
  type        = string
  default     = "ghcr.io/bytefreezer"
}

variable "receiver_url" {
  description = "URL of ByteFreezer receiver webhook endpoint"
  type        = string
}

variable "control_service_url" {
  description = "ByteFreezer control service URL"
  type        = string
}

variable "control_service_api_key_arn" {
  description = "ARN of Secrets Manager secret containing control service API key"
  type        = string
}

variable "desired_count" {
  description = "Desired number of proxy tasks"
  type        = number
  default     = 1
}

variable "udp_port" {
  description = "UDP port for syslog collection"
  type        = number
  default     = 5514
}

variable "cpu" {
  description = "CPU units for proxy task"
  type        = number
  default     = 512
}

variable "memory" {
  description = "Memory (MB) for proxy task"
  type        = number
  default     = 1024
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
