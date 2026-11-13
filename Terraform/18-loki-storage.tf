
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "loki" {
  bucket        = "cs2-loki-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags = { Name = "cs2-loki-logs" }
}

resource "aws_s3_bucket_public_access_block" "loki" {
  bucket                  = aws_s3_bucket.loki.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket_lifecycle_configuration" "loki" {
  bucket = aws_s3_bucket.loki.id
  rule {
    id     = "disaster-backstop-60d"
    status = "Enabled"
    filter {}
    expiration { days = 60 }
  }
}


resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-central-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private_rt.id]
  tags = { Name = "s3-gateway-endpoint" }
}