
resource "aws_route53_zone" "internal" {
  name = "internal.domain"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = { Name = "internal-domain-phz" }
}

resource "aws_route53_record" "grafana" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "grafana.internal.domain"
  type    = "A"
  ttl     = 60
  records = [aws_instance.monitoring_server.private_ip]
}

resource "aws_route53_record" "prometheus" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "prometheus.internal.domain"
  type    = "A"
  ttl     = 60
  records = [aws_instance.monitoring_server.private_ip]
}

resource "aws_route53_record" "vpn" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "tunnel.internal.domain"
  type    = "A"
  ttl     = 60
  records = [aws_instance.tunnel.private_ip]
}
