
resource "tls_private_key" "web" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "web" {
  private_key_pem       = tls_private_key.web.private_key_pem
  validity_period_hours = 8760 # 1 year; a fresh cert is generated on every rebuild anyway

  subject {
    common_name  = "innovatech.local"
    organization = "Echo-Innovatech"
  }

  # SAN matches the ALB hostname so the cert at least identifies the right host
  dns_names = [aws_lb.main_alb.dns_name]

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_acm_certificate" "web" {
  private_key      = tls_private_key.web.private_key_pem
  certificate_body = tls_self_signed_cert.web.cert_pem

  tags = { Name = "web-self-signed-cert" }
}