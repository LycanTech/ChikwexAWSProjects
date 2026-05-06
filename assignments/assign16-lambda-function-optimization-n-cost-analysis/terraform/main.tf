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
# S3 — stores 1000 JSON objects seeded by scripts/seed_s3.py
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "data" {
  bucket        = "${local.prefix}-data-${local.account_id}"
  force_destroy = true
  tags          = { Name = "${local.prefix}-data" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ──────────────────────────────────────────────────────────────────────────────
# DynamoDB — receives processed results from both Lambda versions
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "results" {
  name         = "${local.prefix}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  tags = { Name = "${local.prefix}-results" }
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM — shared execution role for both Lambda functions
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda_exec" {
  name = "${local.prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.prefix}-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Read"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
      },
      {
        Sid    = "DynamoWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:BatchWriteItem"
        ]
        Resource = aws_dynamodb_table.results.arn
      },
      {
        Sid    = "XRay"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${local.prefix}-*"
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda deployment packages
# ──────────────────────────────────────────────────────────────────────────────

data "archive_file" "v1" {
  type        = "zip"
  source_file = "${path.module}/../lambda/v1_unoptimized/handler.py"
  output_path = "${path.module}/../lambda/v1_unoptimized/handler.zip"
}

data "archive_file" "v2" {
  type        = "zip"
  source_file = "${path.module}/../lambda/v2_optimized/handler.py"
  output_path = "${path.module}/../lambda/v2_optimized/handler.zip"
}

# ──────────────────────────────────────────────────────────────────────────────
# CloudWatch log groups (explicit so they are destroyed on terraform destroy)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "v1" {
  name              = "/aws/lambda/${local.prefix}-v1-unoptimized"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "v2" {
  name              = "/aws/lambda/${local.prefix}-v2-optimized"
  retention_in_days = 7
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda v1 — unoptimized baseline (128 MB, sequential reads, individual writes)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "v1" {
  function_name    = "${local.prefix}-v1-unoptimized"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.v1.output_path
  source_code_hash = data.archive_file.v1.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 300

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.data.bucket
      TABLE_NAME    = aws_dynamodb_table.results.name
      OBJECT_PREFIX = var.object_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.v1]
  tags       = { Name = "${local.prefix}-v1-unoptimized" }
}

# ──────────────────────────────────────────────────────────────────────────────
# Lambda v2 — optimized (128 MB start; benchmark script adjusts memory)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_lambda_function" "v2" {
  function_name    = "${local.prefix}-v2-optimized"
  role             = aws_iam_role.lambda_exec.arn
  filename         = data.archive_file.v2.output_path
  source_code_hash = data.archive_file.v2.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  memory_size      = 128
  timeout          = 300

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      BUCKET_NAME   = aws_s3_bucket.data.bucket
      TABLE_NAME    = aws_dynamodb_table.results.name
      OBJECT_PREFIX = var.object_prefix
    }
  }

  depends_on = [aws_cloudwatch_log_group.v2]
  tags       = { Name = "${local.prefix}-v2-optimized" }
}
