# ============================================================
# CS2 M1 — SOAR tunnel: strongSwan site-to-site + dnsmasq DNS
# bridge + Alloy (new-host pattern). pfSense initiates to us.
# On-prem: pfSense 192.168.121.120, lab net 192.168.121.0/24
# ============================================================

# 1. Stable public address for the pfSense peer config
data "aws_eip" "tunnel" {
  id = var.tunnel_eip_allocation_id
}

# 2. Tunnel instance: strongSwan + dnsmasq + Alloy
resource "aws_instance" "tunnel" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_vpn.id
  private_ip = var.tunnel_private_ip
  vpc_security_group_ids      = [aws_security_group.tunnel_sg.id]
  associate_public_ip_address = false
  key_name                    = aws_key_pair.management_key.key_name

  # Required: this box forwards between the VPC and the IPsec SA
  source_dest_check = false

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf install -y libreswan dnsmasq
    dnf install -y docker
    systemctl enable --now docker  dnsmasq
    ipsec initnss >/dev/null 2>&1 || true
    systemctl enable --now ipsec

    cat <<'SYSCTL' > /etc/sysctl.d/99-ipsec.conf
    net.ipv4.ip_forward = 1
    net.ipv4.conf.all.accept_redirects = 0
    net.ipv4.conf.all.send_redirects = 0
    net.ipv4.conf.all.rp_filter = 0
    net.ipv4.conf.default.rp_filter = 0
    SYSCTL
    sysctl --system

    mkdir -p /etc/ipsec.d
    grep -q 'ipsec.d/\*.conf' /etc/ipsec.conf || echo 'include /etc/ipsec.d/*.conf' >> /etc/ipsec.conf
    grep -q 'ipsec.d/\*.secrets' /etc/ipsec.secrets || echo 'include /etc/ipsec.d/*.secrets' >> /etc/ipsec.secrets
    cat > /etc/ipsec.d/onprem.conf <<'IPSEC_EOF'
    conn onprem
        type=tunnel
        auto=add
        authby=secret
        left=%defaultroute
        leftid=${data.aws_eip.tunnel.public_ip}
        leftsubnet=10.0.0.0/16
        right=%any
        rightid=%any
        rightsubnet=172.16.2.0/24
        ikev2=insist
        ike=aes256-sha2_256;dh14
        esp=aes256-sha2_256;dh14
        ikelifetime=8h
        salifetime=1h
        dpddelay=30
        dpdtimeout=120
        dpdaction=clear
        encapsulation=yes
        fragmentation=yes
    IPSEC_EOF

    cat > /etc/ipsec.d/onprem.secrets <<PSK_EOF
    %any %any : PSK "${var.tunnel_psk}"
    PSK_EOF
    chmod 600 /etc/ipsec.d/onprem.secrets

    # dnsmasq: DNS bridge both directions (no-resolv = no loop)
    cat <<'DNSMASQ' > /etc/dnsmasq.conf
    no-resolv
    server=10.0.0.2
    server=/${var.onprem_domain}/${var.onprem_dns}
    server=/121.168.192.in-addr.arpa/${var.onprem_dns}
    domain-needed
    cache-size=1000
    DNSMASQ
    systemctl restart dnsmasq

    # Alloy with embedded unix exporter (CS2 new-host pattern)
    mkdir -p /opt/alloy
    cat <<'ALLOYCONFIG' > /opt/alloy/config.alloy
    prometheus.exporter.unix "local" { }

    prometheus.scrape "unix" {
      targets    = prometheus.exporter.unix.local.targets
      forward_to = [prometheus.remote_write.monitoring.receiver]
    }

    prometheus.remote_write "monitoring" {
      endpoint {
        url = "http://${aws_instance.monitoring_server.private_ip}:9090/api/v1/write"
      }
    }
    ALLOYCONFIG

    docker run -d --name alloy --restart always \
      --network host \
      -v /opt/alloy/config.alloy:/etc/alloy/config.alloy:ro \
      grafana/alloy:v1.5.0 \
      run --server.http.listen-addr=0.0.0.0:12345 /etc/alloy/config.alloy
  EOF
  )

  tags = { Name = "soar-tunnel" }
}

resource "aws_eip_association" "tunnel" {
  instance_id   = aws_instance.tunnel.id
  allocation_id = data.aws_eip.tunnel.id
}

# 4. Route: monitoring/web subnets reach the lab via the tunnel
resource "aws_route" "to_onprem" {
  route_table_id         = aws_route_table.private_rt.id
  destination_cidr_block = var.onprem_cidr
  network_interface_id   = aws_instance.tunnel.primary_network_interface_id
}

# 5. VPC DNS goes through dnsmasq first (on-prem zone), Amazon
#    resolver as fallback so a down tunnel never breaks VPC DNS
resource "aws_vpc_dhcp_options" "main" {
  domain_name         = "${var.aws_region}.compute.internal"
  domain_name_servers = [aws_instance.tunnel.private_ip, "AmazonProvidedDNS"]
  tags = { Name = "main-dhcp-options" }
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.main.id
}