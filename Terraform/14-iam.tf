# IAM role allowing the monitoring server to query EC2 for service discovery
resource "aws_iam_role" "monitoring_role" {
  name = "app-monitoring-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

# Least-privilege policy: only what EC2 service discovery needs
resource "aws_iam_role_policy" "ec2_discovery" {
  name = "app-prometheus-ec2-discovery"
  role = aws_iam_role.monitoring_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeRegions"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy" "loki_s3" {
  name = "loki-s3-access"
  role = aws_iam_role.monitoring_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
        "s3:ListBucket", "s3:AbortMultipartUpload"
      ]
      Resource = [
        aws_s3_bucket.loki.arn,
        "${aws_s3_bucket.loki.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "monitoring_cloudwatch" {
  name = "monitoring-cloudwatch-read"
  role = aws_iam_role.monitoring_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["cloudwatch:ListMetrics", "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics"]
      Resource = "*"
    }]
  })
}


# Allow monitoring EC2 to inspect and test SOAR SQS queues
resource "aws_iam_role_policy" "monitoring_sqs" {
  name = "monitoring-soar-sqs-access"
  role = aws_iam_role.monitoring_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InspectSoarQueues"
        Effect = "Allow"
        Action = [
          "sqs:GetQueueUrl",
          "sqs:GetQueueAttributes"
        ]
        Resource = [
          aws_sqs_queue.soar_events.arn,
          aws_sqs_queue.soar_dlq.arn
        ]
      },
      {
        Sid      = "SendTestMessages"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.soar_events.arn]
      }
    ]
  })
}


resource "aws_iam_instance_profile" "monitoring_profile" {
  name = "app-monitoring-server-profile"
  role = aws_iam_role.monitoring_role.name
}

# Read-only access to SOAR worker logs for triage (guard refusals,
# action outcomes) — complements the dashboard CloudWatch panel.
resource "aws_iam_role_policy" "monitoring_soar_logs" {
  name = "monitoring-soar-cwlogs-read"
  role = aws_iam_role.monitoring_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeLogGroups"
        Effect = "Allow"
        Action = ["logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Sid    = "ReadSoarLogStreams"
        Effect = "Allow"
        Action = ["logs:DescribeLogStreams", "logs:FilterLogEvents", "logs:StartQuery"]
        Resource = "arn:aws:logs:eu-central-1:416291743382:log-group:/ecs/cs2-soar:*"
      },
      {
        Sid    = "RetrieveLogQueryResults"
        Effect = "Allow"
        Action = ["logs:GetQueryResults", "logs:StopQuery"]
        Resource = "*"
      }
    ]
  })
}