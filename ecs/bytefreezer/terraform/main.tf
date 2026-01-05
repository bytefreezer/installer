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
data "aws_caller_identity" "current" {}

locals {
  name_prefix = "bytefreezer-${var.environment}"
  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Application = "bytefreezer"
  })
}

# S3 Buckets
resource "aws_s3_bucket" "intake" {
  bucket = "${var.s3_bucket_prefix}-intake-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "intake" {
  bucket = aws_s3_bucket.intake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "intake" {
  bucket                  = aws_s3_bucket.intake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "piper" {
  bucket = "${var.s3_bucket_prefix}-piper-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "piper" {
  bucket = aws_s3_bucket.piper.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "piper" {
  bucket                  = aws_s3_bucket.piper.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "packer" {
  bucket = "${var.s3_bucket_prefix}-packer-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "packer" {
  bucket = aws_s3_bucket.packer.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "packer" {
  bucket                  = aws_s3_bucket.packer.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "geoip" {
  bucket = "${var.s3_bucket_prefix}-geoip-${data.aws_caller_identity.current.account_id}"
  tags   = local.common_tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "geoip" {
  bucket = aws_s3_bucket.geoip.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "geoip" {
  bucket                  = aws_s3_bucket.geoip.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

# CloudWatch Log Groups
resource "aws_cloudwatch_log_group" "receiver" {
  name              = "/ecs/${local.name_prefix}-receiver"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "piper" {
  name              = "/ecs/${local.name_prefix}-piper"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_cloudwatch_log_group" "packer" {
  name              = "/ecs/${local.name_prefix}-packer"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

# IAM Roles
resource "aws_iam_role" "task_execution" {
  name = "${local.name_prefix}-task-execution"

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

resource "aws_iam_role_policy" "task_s3" {
  name = "s3-access"
  role = aws_iam_role.task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.intake.arn,
        "${aws_s3_bucket.intake.arn}/*",
        aws_s3_bucket.piper.arn,
        "${aws_s3_bucket.piper.arn}/*",
        aws_s3_bucket.packer.arn,
        "${aws_s3_bucket.packer.arn}/*",
        aws_s3_bucket.geoip.arn,
        "${aws_s3_bucket.geoip.arn}/*"
      ]
    }]
  })
}

# Security Groups
resource "aws_security_group" "receiver" {
  name        = "${local.name_prefix}-receiver"
  description = "Security group for ByteFreezer Receiver"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Webhook port"
  }

  ingress {
    from_port   = 8081
    to_port     = 8081
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

resource "aws_security_group" "internal" {
  name        = "${local.name_prefix}-internal"
  description = "Security group for internal ByteFreezer services"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 8082
    to_port         = 8083
    protocol        = "tcp"
    security_groups = [aws_security_group.receiver.id]
    description     = "Internal API access"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

# Application Load Balancer
resource "aws_lb" "receiver" {
  name               = "${local.name_prefix}-receiver"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.receiver.id]
  subnets            = var.subnet_ids

  tags = local.common_tags
}

resource "aws_lb_target_group" "receiver" {
  name        = "${local.name_prefix}-receiver"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/api/v1/health"
    port                = "8081"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "receiver" {
  load_balancer_arn = aws_lb.receiver.arn
  port              = 8080
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.receiver.arn
  }
}

# Receiver Task Definition
resource "aws_ecs_task_definition" "receiver" {
  family                   = "${local.name_prefix}-receiver"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.receiver_cpu
  memory                   = var.receiver_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "receiver"
    image     = "${var.image_registry}/bytefreezer-receiver:${var.image_tag}"
    essential = true

    portMappings = [
      { containerPort = 8080, protocol = "tcp" },
      { containerPort = 8081, protocol = "tcp" }
    ]

    environment = [
      { name = "RECEIVER_S3_BUCKET_NAME", value = aws_s3_bucket.intake.id },
      { name = "RECEIVER_S3_REGION", value = data.aws_region.current.name },
      { name = "RECEIVER_S3_ENDPOINT", value = "s3.${data.aws_region.current.name}.amazonaws.com" },
      { name = "RECEIVER_S3_SSL", value = "true" },
      { name = "RECEIVER_S3_USE_IAM_ROLE", value = "true" },
      { name = "RECEIVER_CONTROL_SERVICE_URL", value = var.control_service_url },
      { name = "RECEIVER_API_PORT", value = "8081" },
      { name = "RECEIVER_WEBHOOK_PORT", value = "8080" }
    ]

    secrets = [{
      name      = "RECEIVER_CONTROL_SERVICE_API_KEY"
      valueFrom = var.control_service_api_key_arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.receiver.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "receiver"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8081/api/v1/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = local.common_tags
}

# Receiver Service
resource "aws_ecs_service" "receiver" {
  name            = "${local.name_prefix}-receiver"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.receiver.arn
  desired_count   = var.receiver_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.receiver.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.receiver.arn
    container_name   = "receiver"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.receiver]

  tags = local.common_tags
}

# Piper Task Definition
resource "aws_ecs_task_definition" "piper" {
  family                   = "${local.name_prefix}-piper"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.piper_cpu
  memory                   = var.piper_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "piper"
    image     = "${var.image_registry}/bytefreezer-piper:${var.image_tag}"
    essential = true

    portMappings = [
      { containerPort = 8082, protocol = "tcp" }
    ]

    environment = [
      { name = "PIPER_S3_SOURCE_BUCKET_NAME", value = aws_s3_bucket.intake.id },
      { name = "PIPER_S3_SOURCE_REGION", value = data.aws_region.current.name },
      { name = "PIPER_S3_SOURCE_ENDPOINT", value = "s3.${data.aws_region.current.name}.amazonaws.com" },
      { name = "PIPER_S3_SOURCE_SSL", value = "true" },
      { name = "PIPER_S3_SOURCE_USE_IAM_ROLE", value = "true" },
      { name = "PIPER_S3_DESTINATION_BUCKET_NAME", value = aws_s3_bucket.piper.id },
      { name = "PIPER_S3_DESTINATION_REGION", value = data.aws_region.current.name },
      { name = "PIPER_S3_DESTINATION_ENDPOINT", value = "s3.${data.aws_region.current.name}.amazonaws.com" },
      { name = "PIPER_S3_DESTINATION_SSL", value = "true" },
      { name = "PIPER_S3_DESTINATION_USE_IAM_ROLE", value = "true" },
      { name = "PIPER_S3_GEOIP_BUCKET_NAME", value = aws_s3_bucket.geoip.id },
      { name = "PIPER_S3_GEOIP_REGION", value = data.aws_region.current.name },
      { name = "PIPER_S3_GEOIP_ENDPOINT", value = "s3.${data.aws_region.current.name}.amazonaws.com" },
      { name = "PIPER_S3_GEOIP_SSL", value = "true" },
      { name = "PIPER_S3_GEOIP_USE_IAM_ROLE", value = "true" },
      { name = "PIPER_CONTROL_SERVICE_URL", value = var.control_service_url },
      { name = "PIPER_API_PORT", value = "8082" },
      { name = "PIPER_DEPLOYMENT_TYPE", value = "on_prem" }
    ]

    secrets = [{
      name      = "PIPER_CONTROL_SERVICE_API_KEY"
      valueFrom = var.control_service_api_key_arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.piper.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "piper"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8082/api/v1/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = local.common_tags
}

# Piper Service
resource "aws_ecs_service" "piper" {
  name            = "${local.name_prefix}-piper"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.piper.arn
  desired_count   = var.piper_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.internal.id]
    assign_public_ip = true
  }

  tags = local.common_tags
}

# Packer Task Definition
resource "aws_ecs_task_definition" "packer" {
  family                   = "${local.name_prefix}-packer"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.packer_cpu
  memory                   = var.packer_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task.arn

  container_definitions = jsonencode([{
    name      = "packer"
    image     = "${var.image_registry}/bytefreezer-packer:${var.image_tag}"
    essential = true

    portMappings = [
      { containerPort = 8083, protocol = "tcp" }
    ]

    environment = [
      { name = "PACKER_S3SOURCE_BUCKET_NAME", value = aws_s3_bucket.piper.id },
      { name = "PACKER_S3SOURCE_REGION", value = data.aws_region.current.name },
      { name = "PACKER_S3SOURCE_ENDPOINT", value = "s3.${data.aws_region.current.name}.amazonaws.com" },
      { name = "PACKER_S3SOURCE_SSL", value = "true" },
      { name = "PACKER_S3SOURCE_USE_IAM_ROLE", value = "true" },
      { name = "PACKER_CONTROL_SERVICE_URL", value = var.control_service_url },
      { name = "PACKER_API_PORT", value = "8083" }
    ]

    secrets = [{
      name      = "PACKER_CONTROL_SERVICE_API_KEY"
      valueFrom = var.control_service_api_key_arn
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.packer.name
        "awslogs-region"        = data.aws_region.current.name
        "awslogs-stream-prefix" = "packer"
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:8083/api/v1/health || exit 1"]
      interval    = 30
      timeout     = 10
      retries     = 3
      startPeriod = 30
    }
  }])

  tags = local.common_tags
}

# Packer Service
resource "aws_ecs_service" "packer" {
  name            = "${local.name_prefix}-packer"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.packer.arn
  desired_count   = var.packer_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.internal.id]
    assign_public_ip = true
  }

  tags = local.common_tags
}
