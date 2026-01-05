output "cluster_name" {
  description = "ECS Cluster name"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ECS Cluster ARN"
  value       = aws_ecs_cluster.main.arn
}

output "proxy_endpoint" {
  description = "Proxy UDP endpoint for sending data"
  value       = "${aws_lb.proxy.dns_name}:${var.udp_port}"
}

output "proxy_api_endpoint" {
  description = "Proxy API endpoint for health checks"
  value       = "http://${aws_lb.proxy.dns_name}:8008"
}

output "nlb_dns_name" {
  description = "Network Load Balancer DNS name"
  value       = aws_lb.proxy.dns_name
}

output "nlb_arn" {
  description = "Network Load Balancer ARN"
  value       = aws_lb.proxy.arn
}

output "service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.proxy.name
}

output "security_group_id" {
  description = "Security group ID for proxy"
  value       = aws_security_group.proxy.id
}
