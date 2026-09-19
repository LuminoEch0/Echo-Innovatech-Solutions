# 1. Application Load Balancer in Public Subnets across both AZs
resource "aws_lb" "main_alb" {
  name               = "main-application-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  
  # ALB requires public subnets in at least 2 Availability Zones
  subnets = [
    aws_subnet.public_1a.id,
    aws_subnet.public_1b.id
  ]

  enable_deletion_protection = false

  tags = {
    Name = "main-alb"
  }
}

# 2. Target Group for Auto Scaling Web Instances
resource "aws_lb_target_group" "web_tg" {
  name     = "web-servers-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  # Health check settings to monitor EC2 web server health
  health_check {
    enabled             = true
    path                = "/"
    port                = "80"
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200"
  }

  tags = {
    Name = "web-target-group"
  }
}

# 3. ALB Listener on Port 80 forwarding to the Web Target Group
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.main_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}