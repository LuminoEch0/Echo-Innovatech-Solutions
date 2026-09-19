# 1. Fetch the latest official Amazon Linux 2023 AMI dynamically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# 2. Launch Template: Installs Docker & runs containerized web app with auto-restart
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-server-template-"
  image_id      = data.aws_ami.amazon_linux_2023.id
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = false # Enforces deployment in private subnets
    security_groups             = [aws_security_group.web_sg.id]
  }

  # User Data script: Installs Docker and starts containerized NGINX web server
  user_data = base64encode(<<-EOF
              #!/bin/bash
              # Doesn't requre updating the system as Amazon Linux 2023 is already up-to-date
              dnf install -y docker
              systemctl start docker
              systemctl enable docker

              # Create app directory & index page
              mkdir -p /var/www/html
              echo "<h1>Hello from Containerized Web Server on EC2!</h1>" > /var/www/html/index.html

              # Run NGINX container mapping host port 80 -> container port 80
              # --restart always ensures Docker re-launches the container if it crashes or reboots
              docker run -d \
                --name web-app \
                --restart always \
                -p 80:80 \
                -v /var/www/html:/usr/share/nginx/html:ro \
                nginx:1.27-alpine
              EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "asg-web-server"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# 3. Auto Scaling Group across Private Compute Subnets AZ-1A and AZ-1B
resource "aws_autoscaling_group" "web_asg" {
  name_prefix         = "web-asg-"
  vpc_zone_identifier = [
    aws_subnet.private_compute_1a.id,
    aws_subnet.private_compute_1b.id
  ]

  target_group_arns = [aws_lb_target_group.web_tg.arn]
  health_check_type = "ELB" # Uses ALB target group health checks and not EC2 instance status checks

  min_size         = 2
  max_size         = 4
  desired_capacity = 2

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  health_check_grace_period = 300

  lifecycle {
    create_before_destroy = true
  }
}

# 4. Target Tracking Scaling Policy: Dynamically scales based on average CPU utilization
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "web-asg-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0
  }
}