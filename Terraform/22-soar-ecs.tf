
resource "aws_security_group" "soar_sg" {
  name        = "soar-task-security-group"
  description = "SOAR webhook listener: ingress only from monitoring (Grafana)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Alert webhook from Grafana"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_sg.id]
  }

  egress {
    description = "Discord / DDB / CloudWatch / SQS via NAT + endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "soar-sg" }
}

resource "aws_ecr_repository" "soar" {
  name                 = "cs2/soar-worker"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  tags = { Name = "cs2-soar-worker" }
}

resource "aws_cloudwatch_log_group" "soar" {
  name              = "/ecs/cs2-soar"
  retention_in_days = 14
}

resource "aws_ecs_cluster" "soar" {
  name = "cs2-soar"
  tags = { Name = "cs2-soar" }
}

resource "aws_service_discovery_private_dns_namespace" "soar" {
  name        = "soar.internal.domain"
  vpc         = aws_vpc.main.id
  description = "Auto-registered A-records for the SOAR Fargate task"
}

resource "aws_service_discovery_service" "soar" {
  name = "soar"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.soar.id
    dns_records {
      ttl  = 15
      type = "A"
    }
    routing_policy = "MULTIVALUE"
  }
}

resource "aws_ecs_task_definition" "soar" {
  family                   = "cs2-soar"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.soar_execution_role.arn
  task_role_arn            = aws_iam_role.soar_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "soar-worker"
      image     = "${aws_ecr_repository.soar.repository_url}:latest"
      essential = true

      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]

      environment = [
        { name = "QUEUE_URL",           value = aws_sqs_queue.soar_events.url },
        { name = "DLQ_URL",             value = aws_sqs_queue.soar_dlq.url },
        { name = "DDB_TABLE",           value = aws_dynamodb_table.soar_events.name },
        { name = "NACL_ID",             value = aws_network_acl.public_vpn.id },
        { name = "NACL_TTL_SECONDS",    value = "600" },
        { name = "DISCORD_WEBHOOK_URL", value = var.discord_webhook_url },
        { name = "WEBHOOK_TOKEN",       value = random_password.soar_token.result },
        { name = "AWS_REGION",          value = var.aws_region }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.soar.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "soar"
        }
      }
    }
  ])

  tags = { Name = "cs2-soar" }
}

resource "aws_ecs_service" "soar" {
  name            = "cs2-soar"
  cluster         = aws_ecs_cluster.soar.id
  task_definition = aws_ecs_task_definition.soar.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.soar_1a.id, aws_subnet.soar_1b.id]
    security_groups  = [aws_security_group.soar_sg.id]
    assign_public_ip = false
  }

  service_registries {
    registry_arn = aws_service_discovery_service.soar.arn
  }
}