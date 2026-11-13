
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions    = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "soar_task_role" {
  name               = "cs2-soar-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy" "soar_actions" {
  name = "cs2-soar-actions"
  role = aws_iam_role.soar_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage", "sqs:DeleteMessage",
          "sqs:GetQueueAttributes", "sqs:GetQueueUrl"
        ]
        Resource = [
          aws_sqs_queue.soar_events.arn,
          aws_sqs_queue.soar_dlq.arn
        ]
      },
      {
        Sid      = "AllowWebhookSendMessages"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = [aws_sqs_queue.soar_events.arn]
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:Query",
          "dynamodb:Scan", "dynamodb:DeleteItem", "dynamodb:UpdateItem"
        ]
        Resource = [aws_dynamodb_table.soar_events.arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkAclEntry", "ec2:DeleteNetworkAclEntry", "ec2:DescribeNetworkAcls"]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = ["*"]
        Condition = {
          StringEquals = { "cloudwatch:namespace" = "CS2/SOAR" }
        }
      }
    ]
  })
}

resource "aws_iam_role" "soar_execution_role" {
  name               = "cs2-soar-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "soar_execution" {
  role       = aws_iam_role.soar_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}