# 1. AWS Key Pair for Secure SSH Access to Management/VPN Host
resource "aws_key_pair" "management_key" {
  key_name   = "management-ssh-key"
  public_key = var.ssh_public_key
}

# 2. OpenVPN / Bastion Gateway in Dedicated Public VPN Subnet
resource "aws_instance" "vpn_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_vpn.id
  vpc_security_group_ids      = [aws_security_group.vpn_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.management_key.key_name

  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf install -y docker
              systemctl start docker
              systemctl enable docker

              # Fetch public IP for OpenVPN client config generation
               # Fetch public IP via IMDSv2 (token required on AL2023)
              TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
                -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
                http://169.254.169.254/latest/meta-data/public-ipv4)
              OVPN_DATA="ovpn-data"

              # Create volume and initialize OpenVPN container automatically
              docker volume create $OVPN_DATA
              docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_genconfig -u udp://$PUBLIC_IP
              docker run -v $OVPN_DATA:/etc/openvpn --rm -e "EASYRSA_BATCH=1" kylemanna/openvpn ovpn_initpki nopass

              # Run OpenVPN server container on UDP 1194
              docker run -v $OVPN_DATA:/etc/openvpn -d \
                --name openvpn \
                -p 1194:1194/udp \
                --cap-add=NET_ADMIN \
                --restart always \
                kylemanna/openvpn
              EOF
  )

  tags = {
    Name = "vpn-management-server"
  }
}

# 3. Persistent Monitoring Server (Prometheus + Grafana) in Private Monitoring Subnet
resource "aws_instance" "monitoring_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.private_monitoring.id
  vpc_security_group_ids      = [aws_security_group.monitoring_sg.id]
  associate_public_ip_address = false

  # Required for Prometheus EC2 service discovery (DescribeInstances API calls)
  iam_instance_profile        = aws_iam_instance_profile.monitoring_profile.name
  key_name                    = aws_key_pair.management_key.key_name


  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf install -y docker
              sudo mkdir -p /usr/local/lib/docker/cli-plugins
              sudo curl -SL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
              sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

              systemctl start docker
              systemctl enable docker

              mkdir -p /opt/monitoring

              cat <<PROMCONFIG > /opt/monitoring/prometheus.yml
              global:
                scrape_interval: 15s

              scrape_configs:
                - job_name: 'prometheus'
                  static_configs:
                    - targets: ['localhost:9090']

                # Dynamic discovery of web servers via the EC2 API.
                - job_name: 'web-servers'
                  ec2_sd_configs:
                    - region: '${var.aws_region}'
                      port: 9100
                      filters:
                        - name: subnet-id
                          values:
                            - '${aws_subnet.private_web_1a.id}'
                            - '${aws_subnet.private_web_1b.id}'
                  relabel_configs:
                    # Label instances by their Name tag + AZ so dashboards can tell replicas apart
                    - source_labels: [__meta_ec2_tag_Name, __meta_ec2_availability_zone]
                      separator: '-'
                      target_label: instance
              PROMCONFIG

              # Generate Docker Compose stack with persistent storage volumes
              cat <<'DOCKERCOMPOSE' > /opt/monitoring/docker-compose.yml
              version: '3.8'

              services:
                prometheus:
                  image: prom/prometheus:v2.54.0
                  container_name: prometheus
                  restart: always
                  ports:
                    - "9090:9090"
                  volumes:
                    - /opt/monitoring/prometheus.yml:/etc/prometheus/prometheus.yml:ro
                    - prometheus_data:/prometheus

                grafana:
                  image: grafana/grafana:11.1.0
                  container_name: grafana
                  restart: always
                  ports:
                    - "3000:3000"
                  environment:
                    - GF_SECURITY_ADMIN_PASSWORD=admin
                  volumes:
                    - grafana_data:/var/lib/grafana

              volumes:
                prometheus_data:
                grafana_data:
              DOCKERCOMPOSE

              # Start monitoring stack
              docker compose -f /opt/monitoring/docker-compose.yml up -d
              EOF
  )

  tags = {
    Name = "private-monitoring-server"
  }
}

