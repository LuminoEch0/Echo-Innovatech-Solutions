
resource "random_password" "soar_token" {
  length  = 32
  special = false
}

resource "aws_sqs_queue" "soar_dlq" {
  name                      = "cs2-soar-dlq"
  message_retention_seconds = 1209600 # 14 days
  tags = { Name = "cs2-soar-dlq" }
}

resource "aws_sqs_queue" "soar_events" {
  name                       = "cs2-soar-events"
  visibility_timeout_seconds = 120
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.soar_dlq.arn
    maxReceiveCount     = 5
  })
  tags = { Name = "cs2-soar-events" }
}

resource "aws_dynamodb_table" "soar_events" {
  name         = "cs2-soar-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = { Name = "cs2-soar-events" }
}