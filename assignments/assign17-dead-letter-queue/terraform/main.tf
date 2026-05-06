terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  prefix     = var.project_name
  account_id = data.aws_caller_identity.current.account_id
}

# ──────────────────────────────────────────────────────────────────────────────
# SNS — DLQ alert topic
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "dlq_alerts" {
  name = "${local.prefix}-dlq-alerts"
  tags = { Name = "${local.prefix}-dlq-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.dlq_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────────────────────────────────────────────────
# SQS Standard — DLQ first (referenced by main queue redrive policy)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "dlq" {
  name                       = "${local.prefix}-failed-messages"
  message_retention_seconds  = 1209600  # 14 days
  visibility_timeout_seconds = 30

  tags = { Name = "${local.prefix}-failed-messages" }
}

resource "aws_sqs_queue" "main" {
  name                       = "${local.prefix}-main-queue"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600  # 4 days

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${local.prefix}-main-queue" }
}

# ──────────────────────────────────────────────────────────────────────────────
# SQS FIFO — with content-based deduplication
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "fifo_dlq" {
  name                        = "${local.prefix}-failed-messages.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  visibility_timeout_seconds  = 30

  tags = { Name = "${local.prefix}-failed-messages.fifo" }
}

resource "aws_sqs_queue" "fifo_main" {
  name                        = "${local.prefix}-main-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 30
  message_retention_seconds   = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.fifo_dlq.arn
    maxReceiveCount     = 3
  })

  tags = { Name = "${local.prefix}-main-queue.fifo" }
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM — consumer Lambda role
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "consumer" {
  name = "${local.prefix}-consumer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "consumer" {
  name = "${local.prefix}-consumer-policy"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = [
          aws_sqs_queue.main.arn,
          aws_sqs_queue.fifo_main.arn
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.prefix}-consumer:*"
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM — DLQ monitor Lambda role
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "dlq_monitor" {
  name = "${local.prefix}-dlq-monitor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dlq_monitor" {
  name = "${local.prefix}-dlq-monitor-policy"
  role = aws_iam_role.dlq_monitor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SQSDLQConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = aws_sqs_queue.dlq.arn
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.dlq_alerts.arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.prefix}-dlq-monitor:*"
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda deployment packages
# ──────────────────────────────────────────────────────────────────────────────

data "archive_file" "consumer" {
  type        = "zip"
  source_file = "${path.module}/../lambda/consumer/handler.py"
  output_path = "${path.module}/../lambda/consumer/handler.zip"
}

data "archive_file" "dlq_monitor" {
  type        = "zip"
  source_file = "${path.module}/../lambda/dlq_monitor/handler.py"
  output_path = "${path.module}/../lambda/dlq_monitor/handler.zip"
}

# ──────────────────────────────────────────────────────────────────────────────
# CloudWatch log groups
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${local.prefix}-consumer"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "dlq_monitor" {
  name              = "/aws/lambda/${local.prefix}-dlq-monitor"
  retention_in_days = 7
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda — consumer (triggered by main-queue)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "consumer" {
  function_name    = "${local.prefix}-consumer"
  role             = aws_iam_role.consumer.arn
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      FAIL_RATE = var.fail_rate
    }
  }

  depends_on = [aws_cloudwatch_log_group.consumer]
  tags       = { Name = "${local.prefix}-consumer" }
}

resource "aws_lambda_event_source_mapping" "main_queue" {
  event_source_arn = aws_sqs_queue.main.arn
  function_name    = aws_lambda_function.consumer.arn
  batch_size       = 1
  enabled          = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda — DLQ monitor (triggered by DLQ)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "dlq_monitor" {
  function_name    = "${local.prefix}-dlq-monitor"
  role             = aws_iam_role.dlq_monitor.arn
  filename         = data.archive_file.dlq_monitor.output_path
  source_code_hash = data.archive_file.dlq_monitor.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.dlq_alerts.arn
      QUEUE_NAME    = aws_sqs_queue.dlq.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.dlq_monitor]
  tags       = { Name = "${local.prefix}-dlq-monitor" }
}

resource "aws_lambda_event_source_mapping" "dlq" {
  event_source_arn = aws_sqs_queue.dlq.arn
  function_name    = aws_lambda_function.dlq_monitor.arn
  batch_size       = 10
  enabled          = true
}
