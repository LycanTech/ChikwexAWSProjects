terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################################################################
# VPC – use the default VPC to keep it simple (free tier)
###############################################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

###############################################################################
# Security Groups
###############################################################################
resource "aws_security_group" "rds" {
  name        = "${var.prefix}-rds-sg"
  description = "Allow MySQL from Lambda"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "MySQL from Lambda"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-rds-sg" }
}

resource "aws_security_group" "lambda" {
  name        = "${var.prefix}-lambda-sg"
  description = "Lambda outbound to RDS and Secrets Manager"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.prefix}-lambda-sg" }
}

###############################################################################
# RDS Subnet Group
###############################################################################
resource "aws_db_subnet_group" "main" {
  name       = "${var.prefix}-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = { Name = "${var.prefix}-db-subnet-group" }
}

###############################################################################
# Secrets Manager – initial secret
###############################################################################
resource "aws_secretsmanager_secret" "rds" {
  name                    = "${var.prefix}/rds/master"
  description             = "RDS master credentials"
  recovery_window_in_days = 0  # allow immediate delete for lab

  tags = { Name = "${var.prefix}-rds-secret" }
}

resource "aws_secretsmanager_secret_version" "rds_initial" {
  secret_id = aws_secretsmanager_secret.rds.id
  secret_string = jsonencode({
    username            = var.db_master_username
    password            = var.db_master_password
    engine              = "mysql"
    host                = aws_db_instance.main.address
    port                = 3306
    dbname              = var.db_name
    dbInstanceIdentifier = aws_db_instance.main.identifier
  })

  # Re-created whenever rotation updates the secret outside Terraform
  lifecycle {
    ignore_changes = [secret_string]
  }
}

###############################################################################
# RDS MySQL – free tier (db.t3.micro, no Multi-AZ, no encryption for lab)
###############################################################################
resource "aws_db_instance" "main" {
  identifier              = "${var.prefix}-mysql"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp2"
  db_name                 = var.db_name
  username                = var.db_master_username
  password                = var.db_master_password
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  multi_az                = false

  tags = { Name = "${var.prefix}-mysql" }
}

###############################################################################
# IAM – Rotation Lambda
###############################################################################
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rotation_lambda" {
  name               = "${var.prefix}-rotation-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name = "${var.prefix}-rotation-lambda-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = aws_secretsmanager_secret.rds.arn
      },
      {
        Sid    = "VpcNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

###############################################################################
# IAM – App Lambda
###############################################################################
resource "aws_iam_role" "app_lambda" {
  name               = "${var.prefix}-app-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "app_lambda" {
  name = "${var.prefix}-app-lambda-policy"
  role = aws_iam_role.app_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadSecret"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.rds.arn
      },
      {
        Sid    = "VpcNetworking"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeNetworkInterfaces"
        ]
        Resource = "*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

###############################################################################
# CloudWatch Log Groups – pre-create so they exist before first invocation
###############################################################################
resource "aws_cloudwatch_log_group" "rotation_lambda" {
  name              = "/aws/lambda/${var.prefix}-rds-rotation"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "app_lambda" {
  name              = "/aws/lambda/${var.prefix}-rds-app"
  retention_in_days = 7
}

###############################################################################
# Lambda – Rotation Function
###############################################################################
data "archive_file" "rotation" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/rotation"
  output_path = "${path.module}/rotation_lambda.zip"
}

resource "aws_lambda_function" "rotation" {
  function_name    = "${var.prefix}-rds-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "rotation.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256
  timeout          = 60
  memory_size      = 128

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${var.region}.amazonaws.com"
    }
  }

  tags = { Name = "${var.prefix}-rds-rotation" }

  depends_on = [aws_cloudwatch_log_group.rotation_lambda]
}

# Allow Secrets Manager to invoke the rotation Lambda
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
  source_account = data.aws_caller_identity.current.account_id
}

###############################################################################
# Lambda – App Function
###############################################################################
data "archive_file" "app" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/app"
  output_path = "${path.module}/app_lambda.zip"
}

resource "aws_lambda_function" "app" {
  function_name    = "${var.prefix}-rds-app"
  role             = aws_iam_role.app_lambda.arn
  handler          = "app.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.app.output_path
  source_code_hash = data.archive_file.app.output_base64sha256
  timeout          = 30
  memory_size      = 128

  vpc_config {
    subnet_ids         = data.aws_subnets.default.ids
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SECRET_ARN = aws_secretsmanager_secret.rds.arn
    }
  }

  tags = { Name = "${var.prefix}-rds-app" }

  depends_on = [aws_cloudwatch_log_group.app_lambda]
}

###############################################################################
# Secrets Manager Rotation Schedule
###############################################################################
resource "aws_secretsmanager_secret_rotation" "rds" {
  secret_id           = aws_secretsmanager_secret.rds.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 7
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}
