variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "production"
}

variable "vpc_id" {
  description = "VPC ID to deploy into"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for ECS tasks (minimum 2 for ALB)"
  type        = list(string)
}

variable "image_tag" {
  description = "Docker image tag for ByteFreezer images"
  type        = string
  default     = "latest"
}

variable "image_registry" {
  description = "Docker image registry"
  type        = string
  default     = "ghcr.io/bytefreezer"
}

variable "control_service_url" {
  description = "ByteFreezer control service URL"
  type        = string
}

variable "control_service_api_key_arn" {
  description = "ARN of Secrets Manager secret containing control service API key"
  type        = string
}

variable "s3_bucket_prefix" {
  description = "Prefix for S3 bucket names"
  type        = string
  default     = "bytefreezer"
}

variable "receiver_desired_count" {
  description = "Desired number of receiver tasks"
  type        = number
  default     = 1
}

variable "piper_desired_count" {
  description = "Desired number of piper tasks"
  type        = number
  default     = 1
}

variable "packer_desired_count" {
  description = "Desired number of packer tasks"
  type        = number
  default     = 1
}

variable "receiver_cpu" {
  description = "CPU units for receiver task"
  type        = number
  default     = 512
}

variable "receiver_memory" {
  description = "Memory (MB) for receiver task"
  type        = number
  default     = 1024
}

variable "piper_cpu" {
  description = "CPU units for piper task"
  type        = number
  default     = 1024
}

variable "piper_memory" {
  description = "Memory (MB) for piper task"
  type        = number
  default     = 2048
}

variable "packer_cpu" {
  description = "CPU units for packer task"
  type        = number
  default     = 1024
}

variable "packer_memory" {
  description = "Memory (MB) for packer task"
  type        = number
  default     = 2048
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
