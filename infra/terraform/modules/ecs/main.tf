# ECS Fargate: serverless containers. No EC2 instances to patch.
# Two services (backend, frontend), each with:
#   - a task definition (image, CPU/RAM, env vars, secrets, logging)
#   - rolling deploys with a circuit breaker (auto-rollback on failure)
#   - CPU-based autoscaling between min and max tasks

data "aws_region" "current" {}

locals {
  region        = data.aws_region.current.name
  service_names = toset(["backend", "frontend"])

  services = {
    backend = {
      image         = "${var.backend_image_repo}:${var.image_tag}"
      port          = 8000
      cpu           = var.backend_cpu
      memory        = var.backend_memory
      desired       = var.backend_min_count
      min           = var.backend_min_count
      max           = var.backend_max_count
      target_group  = var.backend_target_group_arn
      task_role_arn = aws_iam_role.backend_task.arn
      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "APP_VERSION", value = var.image_tag },
        { name = "DB_HOST", value = var.db_host },
        { name = "DB_PORT", value = tostring(var.db_port) },
        { name = "DB_NAME", value = var.db_name },
        { name = "WEB_CONCURRENCY", value = "2" },
        { name = "LOG_LEVEL", value = "INFO" },
      ]
      # Pulled from Secrets Manager by the ECS agent at start-up, never visible in the console
      secrets = [
        { name = "DB_USER", valueFrom = "${var.db_secret_arn}:username::" },
        { name = "DB_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      ]
    }
    frontend = {
      image         = "${var.frontend_image_repo}:${var.image_tag}"
      port          = 3000
      cpu           = var.frontend_cpu
      memory        = var.frontend_memory
      desired       = var.frontend_min_count
      min           = var.frontend_min_count
      max           = var.frontend_max_count
      target_group  = var.frontend_target_group_arn
      task_role_arn = aws_iam_role.frontend_task.arn
      environment = [
        { name = "NODE_ENV", value = "production" },
      ]
      secrets = []
    }
  }
}

# ------------------------------------------------------------------ cluster
resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "enabled" # per-task CPU/memory/network metrics in CloudWatch
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }
}

resource "aws_cloudwatch_log_group" "svc" {
  for_each          = local.service_names
  name              = "/ecs/${var.name}/${each.key}"
  retention_in_days = var.log_retention_days
}

# ------------------------------------------------------------------ IAM
# Execution role = what the ECS *agent* needs (pull image, write logs, read secrets)
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-db-secret"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = var.db_secret_arn
    }]
  })
}

# Task roles = what *your application code* may do in AWS. Empty on purpose:
# add permissions only when the app actually needs them (e.g. S3 uploads).
resource "aws_iam_role" "backend_task" {
  name               = "${var.name}-backend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role" "frontend_task" {
  name               = "${var.name}-frontend-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

# ECS Exec ("docker exec" into a running Fargate task, for debugging)
resource "aws_iam_role_policy" "backend_exec" {
  name = "ecs-exec"
  role = aws_iam_role.backend_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"
      ]
      Resource = "*"
    }]
  })
}

# ------------------------------------------------------------------ task definitions
resource "aws_ecs_task_definition" "svc" {
  for_each                 = local.service_names
  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.services[each.key].cpu
  memory                   = local.services[each.key].memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = local.services[each.key].task_role_arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name         = each.key
    image        = local.services[each.key].image
    essential    = true
    portMappings = [{ containerPort = local.services[each.key].port, protocol = "tcp" }]
    environment  = local.services[each.key].environment
    secrets      = local.services[each.key].secrets
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.svc[each.key].name
        awslogs-region        = local.region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

# ------------------------------------------------------------------ services
resource "aws_ecs_service" "svc" {
  for_each               = local.service_names
  name                   = each.key
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.svc[each.key].arn
  desired_count          = local.services[each.key].desired
  enable_execute_command = each.key == "backend"
  propagate_tags         = "SERVICE"

  capacity_provider_strategy {
    capacity_provider = var.use_fargate_spot ? "FARGATE_SPOT" : "FARGATE"
    weight            = 1
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = local.services[each.key].target_group
    container_name   = each.key
    container_port   = local.services[each.key].port
  }

  # Rolling deploy: start new tasks first (200%), never drop below 100% healthy.
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  # If new tasks keep failing health checks, ECS rolls back automatically.
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    # CI/CD owns the running image version and autoscaling owns the count.
    # Without this, every `terraform apply` would undo the last deploy.
    ignore_changes = [task_definition, desired_count]
  }

  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

# ------------------------------------------------------------------ autoscaling
resource "aws_appautoscaling_target" "svc" {
  for_each           = local.service_names
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.svc[each.key].name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = local.services[each.key].min
  max_capacity       = local.services[each.key].max
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each           = local.service_names
  name               = "${var.name}-${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.svc[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.svc[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.svc[each.key].scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60 # keep average CPU around 60%
    scale_in_cooldown  = 120
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
