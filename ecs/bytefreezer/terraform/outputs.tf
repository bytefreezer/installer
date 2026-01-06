output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "receiver_url" {
  description = "Receiver webhook URL for proxy configuration"
  value       = "http://${aws_lb.receiver.dns_name}:8080"
}

output "receiver_alb_dns" {
  description = "Receiver ALB DNS name"
  value       = aws_lb.receiver.dns_name
}

output "intake_bucket_name" {
  description = "S3 bucket for raw data intake"
  value       = aws_s3_bucket.intake.id
}

output "intake_bucket_arn" {
  description = "S3 bucket ARN for raw data intake"
  value       = aws_s3_bucket.intake.arn
}

output "piper_bucket_name" {
  description = "S3 bucket for processed data"
  value       = aws_s3_bucket.piper.id
}

output "piper_bucket_arn" {
  description = "S3 bucket ARN for processed data"
  value       = aws_s3_bucket.piper.arn
}

output "geoip_bucket_name" {
  description = "S3 bucket for GeoIP databases"
  value       = aws_s3_bucket.geoip.id
}

output "receiver_service_name" {
  description = "Receiver ECS service name"
  value       = aws_ecs_service.receiver.name
}

output "piper_service_name" {
  description = "Piper ECS service name"
  value       = aws_ecs_service.piper.name
}

output "packer_service_name" {
  description = "Packer ECS service name"
  value       = aws_ecs_service.packer.name
}

output "receiver_security_group_id" {
  description = "Security group ID for receiver"
  value       = aws_security_group.receiver.id
}

output "internal_security_group_id" {
  description = "Security group ID for internal services"
  value       = aws_security_group.internal.id
}
