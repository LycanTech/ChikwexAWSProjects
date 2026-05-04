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

locals {
  prefix = var.project_name
}

# ──────────────────────────────────────────────────────────────────────────────
# SNS topic – all three Lambda functions publish here
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "notifications" {
  name = "${local.prefix}-eventbridge-notifications"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM role shared by all three Lambda functions
# ──────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.prefix}-eventbridge-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "basic_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_perms" {
  # EC2 scheduler
  statement {
    sid     = "EC2ReadAndControl"
    actions = [
      "ec2:DescribeInstances",
      "ec2:StartInstances",
      "ec2:StopInstances",
    ]
    resources = ["*"]
  }

  # Snapshot cleanup
  statement {
    sid     = "SnapshotCleanup"
    actions = [
      "ec2:DescribeSnapshots",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }

  # Security group check
  statement {
    sid     = "SecurityGroupRead"
    actions = ["ec2:DescribeSecurityGroups"]
    resources = ["*"]
  }

  # SNS publish
  statement {
    sid     = "SNSPublish"
    actions = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
}

resource "aws_iam_role_policy" "lambda_perms" {
  name   = "${local.prefix}-lambda-perms"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.lambda_perms.json
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda zip packages
# ──────────────────────────────────────────────────────────────────────────────

data "archive_file" "ec2_scheduler" {
  type        = "zip"
  source_file = "${path.module}/lambda/ec2_scheduler.py"
  output_path = "${path.module}/lambda/ec2_scheduler.zip"
}

data "archive_file" "snapshot_cleanup" {
  type        = "zip"
  source_file = "${path.module}/lambda/snapshot_cleanup.py"
  output_path = "${path.module}/lambda/snapshot_cleanup.zip"
}

data "archive_file" "security_check" {
  type        = "zip"
  source_file = "${path.module}/lambda/security_check.py"
  output_path = "${path.module}/lambda/security_check.zip"
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda 1 – EC2 scheduler (every 5 minutes)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "ec2_scheduler" {
  function_name    = "${local.prefix}-ec2-scheduler"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "ec2_scheduler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ec2_scheduler.output_path
  source_code_hash = data.archive_file.ec2_scheduler.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "ec2_scheduler" {
  name                = "${local.prefix}-ec2-scheduler"
  description         = "Trigger EC2 start/stop Lambda every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "ec2_scheduler" {
  rule      = aws_cloudwatch_event_rule.ec2_scheduler.name
  target_id = "ec2SchedulerLambda"
  arn       = aws_lambda_function.ec2_scheduler.arn
}

resource "aws_lambda_permission" "ec2_scheduler" {
  statement_id  = "AllowEventBridgeEC2Scheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ec2_scheduler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.ec2_scheduler.arn
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda 2 – weekly snapshot cleanup (Sunday 2 am UTC)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "snapshot_cleanup" {
  function_name    = "${local.prefix}-snapshot-cleanup"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "snapshot_cleanup.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.snapshot_cleanup.output_path
  source_code_hash = data.archive_file.snapshot_cleanup.output_base64sha256
  timeout          = 300

  environment {
    variables = {
      SNS_TOPIC_ARN   = aws_sns_topic.notifications.arn
      RETENTION_DAYS  = tostring(var.snapshot_retention_days)
    }
  }
}

resource "aws_cloudwatch_event_rule" "snapshot_cleanup" {
  name                = "${local.prefix}-snapshot-cleanup"
  description         = "Weekly snapshot cleanup every Sunday at 2am UTC"
  schedule_expression = "cron(0 2 ? * SUN *)"
}

resource "aws_cloudwatch_event_target" "snapshot_cleanup" {
  rule      = aws_cloudwatch_event_rule.snapshot_cleanup.name
  target_id = "snapshotCleanupLambda"
  arn       = aws_lambda_function.snapshot_cleanup.arn
}

resource "aws_lambda_permission" "snapshot_cleanup" {
  statement_id  = "AllowEventBridgeSnapshotCleanup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.snapshot_cleanup.arn
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda 3 – security group check (every hour)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "security_check" {
  function_name    = "${local.prefix}-security-check"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "security_check.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.security_check.output_path
  source_code_hash = data.archive_file.security_check.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.notifications.arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "security_check" {
  name                = "${local.prefix}-security-check"
  description         = "Hourly check for security groups exposing SSH to the world"
  schedule_expression = "rate(1 hour)"
}

resource "aws_cloudwatch_event_target" "security_check" {
  rule      = aws_cloudwatch_event_rule.security_check.name
  target_id = "securityCheckLambda"
  arn       = aws_lambda_function.security_check.arn
}

resource "aws_lambda_permission" "security_check" {
  statement_id  = "AllowEventBridgeSecurityCheck"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.security_check.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_check.arn
}
