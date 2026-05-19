terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
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
# Permission Boundary — caps what developer-test can ever do
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "permission_boundary" {
  name        = "${local.prefix}-permission-boundary"
  description = "Permission boundary for developer-test: S3 read-only, EC2 micro only, no IAM escalation"
  policy      = file("${path.module}/../policies/permission_boundary.json")

  tags = {
    Project     = local.prefix
    Environment = "test"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Custom Developer Policy
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_policy" "developer_policy" {
  name        = "${local.prefix}-developer-policy"
  description = "Read-only S3 (Team:Dev tagged), EC2 micro launch, dev-VPC create/delete only"

  policy = templatefile("${path.module}/../policies/developer_policy.json", {
    dev_vpc_id = var.dev_vpc_id
  })

  tags = {
    Project     = local.prefix
    Environment = "test"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM User — developer-test
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_user" "developer_test" {
  name                 = "developer-test"
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  force_destroy        = true

  tags = {
    Project     = local.prefix
    Environment = "test"
    Team        = "Dev"
  }
}

resource "aws_iam_user_policy_attachment" "developer_policy_attach" {
  user       = aws_iam_user.developer_test.name
  policy_arn = aws_iam_policy.developer_policy.arn
}

resource "aws_iam_access_key" "developer_test" {
  user = aws_iam_user.developer_test.name
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM Role — developer-test-role (for assume-role + session policy tests)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "developer_role" {
  name                 = "${local.prefix}-developer-role"
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  description          = "Role assumed by developer-test for session policy testing"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = aws_iam_user.developer_test.arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:TransitiveTagKey" = ["Team"]
          }
        }
      }
    ]
  })

  tags = {
    Project     = local.prefix
    Environment = "test"
  }
}

resource "aws_iam_role_policy_attachment" "developer_role_policy" {
  role       = aws_iam_role.developer_role.name
  policy_arn = aws_iam_policy.developer_policy.arn
}

# Allow developer-test user to assume the role
resource "aws_iam_user_policy" "allow_assume_role" {
  name = "${local.prefix}-allow-assume-role"
  user = aws_iam_user.developer_test.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AllowAssumeDevRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.developer_role.arn
      }
    ]
  })
}

# ──────────────────────────────────────────────────────────────────────────────
# IAM Access Analyzer — account-level analyzer
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_accessanalyzer_analyzer" "account_analyzer" {
  analyzer_name = "${local.prefix}-account-analyzer"
  type          = "ACCOUNT"

  tags = {
    Project     = local.prefix
    Environment = "test"
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# SNS topic for Access Analyzer findings (optional alerting)
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "analyzer_alerts" {
  name = "${local.prefix}-analyzer-alerts"

  tags = {
    Project     = local.prefix
    Environment = "test"
  }
}

resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.analyzer_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ──────────────────────────────────────────────────────────────────────────────
# EventBridge rule: notify on new Access Analyzer findings
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "analyzer_finding" {
  name        = "${local.prefix}-analyzer-finding"
  description = "Trigger SNS when Access Analyzer creates a new finding"

  event_pattern = jsonencode({
    source      = ["aws.access-analyzer"]
    detail-type = ["Access Analyzer Finding"]
    detail = {
      status = ["ACTIVE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "analyzer_sns" {
  rule      = aws_cloudwatch_event_rule.analyzer_finding.name
  target_id = "AnalyzerFindingSNS"
  arn       = aws_sns_topic.analyzer_alerts.arn
}

resource "aws_sns_topic_policy" "allow_eventbridge" {
  arn = aws_sns_topic.analyzer_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.analyzer_alerts.arn
      }
    ]
  })
}
