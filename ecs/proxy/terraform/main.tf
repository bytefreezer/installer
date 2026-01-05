terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_region" "current" {}

locals {
  name_prefix = "bf-proxy-${var.site_name}-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    Site        = var.site_name
    ManagedBy   = "terraform"
    Application = "bytefreezer-proxy"
  })
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "proxy" {
  name              = "/ecs/${local.name_prefix}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# IAM Roles
resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "task_execution_secrets" {
  name = "secrets-access"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [var.control_service_api_key_arn]
    }]
  })
}

resource "aws_iam_role" "task" {
  name = "${local.name_prefix}-task"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })

  tags = local.common_tags
}

# Security Group
resource "aws_security_group" "proxy" {
  name        = local.name_prefix
  description = "Security group for ByteFreezer Proxy"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.udp_port
    to_port     = var.udp_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "UDP syslog port"
  }

  ingress {
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "API port"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Network Load Balancer (required for UDP)
resource "aws_lb" "proxy" {
  name               = local.name_prefix
  internal           = false
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  tags = local.common_tags
}

# UDP Target Group
resource "aws_lb_target_group" "udp" {
  name        = "${local.name_prefix}-udp"
  port        = var.udp_port
  protocol    = "UDP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "8008"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

# UDP Listener
resource "aws_lb_listener" "udp" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = var.udp_port
  protocol          = "UDP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.udp.arn
  }
}

# TCP Target Group (for API access)
resource "aws_lb_target_group" "tcp" {
  name        = "${local.name_prefix}-tcp"
  port        = 8008
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    protocol            = "TCP"
    port                = "8008"
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

# TCP Listener (for API access)
resource "aws_lb_listener" "tcp" {
  load_balancer_arn = aws_lb.proxy.arn
  port              = 8008
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tcp.arn
  }
}

# Proxy Task Definition
resource "aws_ecs_task_definition" "proxy" {
  family                   = local.name_prefix
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.cpu
  memory                   = var.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "proxy"
    image     = "${var.image_registry}/bytefreezer-proxy:${var.image_tag}"
    essential = true

    portMappings = [
      { containerPort = var.udp_port, protocol = "udp" },
      { containerPort = 8008, protocol = "tcp" }
    ]

    environment = [
      { name = "PROXY_RECEIVER_URL", value = var.receiver_url },
      { name = "PROXY_CONTROL_SERVICE_URL", value = var.control_service_url },
      { name = "PROXY_API_PORT", value = "8008" },
      { name = "PROXY_UDP_ENABLED", value = "true" },
      { name = "PROXY_UDP_PORT", value = tostring(var.udp_port) },
      { name = "PROXY_BATCHING_ENABLED", value = "true" },
      { name = "PROXY_BATCHING_MAX_LINES", value = "10000" },
      { name = "PROXY_BATCHING_MAX_BYTES", value = "10485760" },
      { name = "PROXY_BATCHING_TIMEOUT_SECONDS", value = "30" },
      { name = "PROXY_SPOOLING_ENABLED", value = "true" },
      { name = "PROXY_SPOOLING_MAX_SIZE_BYTES", value = "1073741824" },
      { name = "PROXY_HEALTH_REPORTING_ENABLED", value = "true" },
      { name = "PROXY_HEALTH_REPORTING_INTERVAL", value = "30" }
    ]

    secrets = [{
      name      = "PROXY_CONTROL_SERVICE_API_KEY"
      valueFrom = var.control_service_api_key_arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.proxy.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "proxy"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8008/api/v1/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = local.common_tags
}

# Proxy Service
resource "aws_ecs_service" "proxy" {
  name            = local.name_prefix
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.proxy.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.proxy.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.udp.arn
    container_name   = "proxy"
    container_port   = var.udp_port
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tcp.arn
    container_name   = "proxy"
    container_port   = 8008
  }

  depends_on = [aws_lb_listener.udp, aws_lb_listener.tcp]

  tags = local.common_tags
}
