# 1. Application Load Balancer Security Group
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Allow public HTTP/HTTPS traffic to the ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from Internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from Internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "alb-sg"
  }
}

# 2. OpenVPN Server Security Group
resource "aws_security_group" "vpn_sg" {
  name        = "vpn-security-group"
  description = "Allow VPN connection from management network"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "OpenVPN UDP"
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH Access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "vpn-sg"
  }
}

# 3. Web Servers Security Group
resource "aws_security_group" "web_sg" {
  name        = "web-servers-security-group"
  description = "Allow HTTP from ALB and SSH/Monitoring internally"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP traffic from ALB only"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  ingress {
    description     = "SSH management from VPN server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_sg.id]
  }

  ingress {
    description     = "Node Exporter metrics for Monitoring server"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitoring_sg.id]
  }

  egress {
    description = "Allow outbound to pull updates via NAT Gateway"
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-sg"
  }
}

# 4. Monitoring Server Security Group
resource "aws_security_group" "monitoring_sg" {
  name        = "monitoring-security-group"
  description = "Allow Grafana/Prometheus dashboard access via VPN"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Prometheus/Grafana web UI from VPN"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_sg.id]
  }

  ingress {
    description     = "SSH from VPN"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_sg.id]
  }

  egress {
    description = "Allow all outbound traffic to scrape targets"
    from_port   = 0
    to_port     = 0
    protocol    ="-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "monitoring-sg"
  }
}

# 5. PostgreSQL RDS Database Security Group
resource "aws_security_group" "db_sg" {
  name        = "db-security-group"
  description = "Allow PostgreSQL access strictly from Web and VPN"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from Web instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.web_sg.id]
  }

  ingress {
    description     = "PostgreSQL management from VPN"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.vpn_sg.id]
  }

 # No outbound rules are defined, so the database is cannot communicate with the outside world.

  tags = {
    Name = "db-sg"
  }
}