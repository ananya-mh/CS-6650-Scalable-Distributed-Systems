terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

provider "docker" {
  registry_auth {
    address  = data.aws_ecr_authorization_token.token.proxy_endpoint
    username = data.aws_ecr_authorization_token.token.user_name
    password = data.aws_ecr_authorization_token.token.password
  }
}


# If you're also using these, add them too:
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}


data "aws_iam_role" "ecs_task_execution_role" {
  name = "MyRole" 
}

# For task role, often you can use the same role
data "aws_iam_role" "ecs_task_role" {
  name = "MyRole" 
}

###################################################
#  VPC and Subnets Data Sources
###################################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "product-search-vpc"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet 1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "Public Subnet 2"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "Main IGW"
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "Public Route Table"
  }
}

# Associate route table with subnets
resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

###################################################
# ECR Repository
###################################################

resource "aws_ecr_repository" "app" {
  name                 = "product-search-api"
  image_tag_mutability = "MUTABLE"
  force_delete        = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_ecr_authorization_token" "token" {}

###################################################
# Build and Push Docker Image
###################################################

resource "docker_image" "app" {
  name = "${aws_ecr_repository.app.repository_url}:latest"
  
  build {
    context    = ".."
    dockerfile = "Dockerfile"
  }
}

resource "docker_registry_image" "app" {
  name = docker_image.app.name
  
  triggers = {
    image_id = docker_image.app.image_id
  }
}

###################################################
# ECS Cluster
###################################################

resource "aws_ecs_cluster" "main" {
  name = "product-search-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name = aws_ecs_cluster.main.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

###################################################
# ECS Task Definition
###################################################

resource "aws_ecs_task_definition" "app" {
  family                   = "product-search-task"
  network_mode            = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                     = "256"
  memory                  = "512"
  execution_role_arn      = data.aws_iam_role.ecs_task_execution_role.arn
  task_role_arn           = data.aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "product-search"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    
    essential = true
    
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
        "awslogs-region"        = "us-west-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
    
    healthCheck = {
      command     = ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])
  
  depends_on = [docker_registry_image.app]
}

###################################################
# ECS Service with ALB
###################################################

resource "aws_ecs_service" "app" {
  name            = "product-search-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1  # Run 1 instance for HA
  launch_type     = "FARGATE"

  network_configuration {
    security_groups  = [aws_security_group.ecs_tasks.id]
    subnets         = [aws_subnet.public_1.id, aws_subnet.public_2.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "product-search"
    container_port   = 8080
  }
  
  depends_on = [aws_lb_listener.app]
}

###################################################
# Application Load Balancer
###################################################

resource "aws_lb" "main" {
  name               = "product-search-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets           = [aws_subnet.public_1.id, aws_subnet.public_2.id]

  enable_deletion_protection = false
  enable_http2              = true
}

resource "aws_lb_target_group" "app" {
  name        = "product-search-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/health"
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher            = "200"
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_security_group" "alb" {
  name        = "product-search-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ecs_tasks" {
  name        = "product-search-ecs-tasks-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}


###################################################
# CloudWatch Logs
###################################################

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/product-search"
  retention_in_days = 7
}

###################################################
# Outputs
###################################################

output "alb_endpoint" {
  value = "http://${aws_lb.main.dns_name}"
}

# output "api_gateway_endpoint" {
#   value = aws_apigatewayv2_api.app.api_endpoint
# }

output "health_url" {
  value = "http://${aws_lb.main.dns_name}/health"
}

output "search_url" {
  value = "http://${aws_lb.main.dns_name}/products/search?q=test"
}