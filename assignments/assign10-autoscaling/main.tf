# ═══════════════════════════════════════════════════════════════════════════════
# Assignment 10 – Auto Scaling Group with Lifecycle Hooks
#
# Flow:
#   EC2 launches → ASG Lifecycle Hook pauses instance at "Pending:Wait"
#   → EventBridge fires → Lambda runs SSM Run Command on the instance
#   → installs httpd, writes unique index.html, starts httpd
#   → Lambda calls CompleteLifecycleAction(CONTINUE)
#   → instance moves to InService
#   CloudWatch Alarm (CPU > 60 %) → Step Scaling Policy adds 1 instance
# ═══════════════════════════════════════════════════════════════════════════════

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

# ── Data sources ───────────────────────────────────────────────────────────────

# Re-use the default VPC so students don't need to create networking
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Latest Amazon Linux 2023 AMI (x86_64)
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── Security group ─────────────────────────────────────────────────────────────
# Allow HTTP inbound so we can curl the web pages, and all egress for package installs.

resource "aws_security_group" "web" {
  name        = "${var.project_name}-web-sg"
  description = "Allow HTTP inbound for web server verification"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-web-sg" }
}

# ── IAM: EC2 instance profile ──────────────────────────────────────────────────
# Instances need AmazonSSMManagedInstanceCore so the SSM agent can receive
# Run Command documents from Lambda.

resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project_name}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ── Launch Template ────────────────────────────────────────────────────────────
# Defines the AMI, instance type, security group, and instance profile.
# No user data — configuration is handled entirely by the Lambda + SSM flow.

resource "aws_launch_template" "web" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_ssm.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.web.id]
  }

  # IMDSv2 enforced (required by the metadata fetch in the Lambda script)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-instance" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ── Auto Scaling Group ─────────────────────────────────────────────────────────

resource "aws_autoscaling_group" "web" {
  name                = "${var.project_name}-asg"
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = data.aws_subnets.default.ids

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  # Health check — EC2 level is sufficient since there is no load balancer
  health_check_type         = "EC2"
  health_check_grace_period = 300

  # Propagate ASG name tag to instances
  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }

  # The lifecycle hook is defined separately below; ASG must exist first.
  lifecycle {
    ignore_changes = [desired_capacity]
  }
}

# ── Lifecycle Hook ─────────────────────────────────────────────────────────────
# Intercepts the instance at "Pending:Wait" during launch.
# The instance stays paused until Lambda calls CompleteLifecycleAction.
# heartbeat_timeout is the maximum seconds allowed before the hook
# automatically times out (default action = ABANDON).

resource "aws_autoscaling_lifecycle_hook" "launch" {
  name                    = "${var.project_name}-launch-hook"
  autoscaling_group_name  = aws_autoscaling_group.web.name
  lifecycle_transition    = "autoscaling:EC2_INSTANCE_LAUNCHING"
  default_result          = "ABANDON"
  heartbeat_timeout       = var.lifecycle_heartbeat_timeout
}

# ── IAM: Lambda execution role ─────────────────────────────────────────────────
# Lambda needs:
#   - CloudWatch Logs (basic execution)
#   - SSM SendCommand + GetCommandInvocation (to configure the instance)
#   - SSM DescribeInstanceInformation (to poll SSM agent readiness)
#   - autoscaling:CompleteLifecycleAction (to signal the hook)

resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_inline" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      # SSM — send and track commands
      {
        Effect = "Allow"
        Action = [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation"
        ]
        Resource = "*"
      },
      # ASG — complete the lifecycle hook
      {
        Effect   = "Allow"
        Action   = ["autoscaling:CompleteLifecycleAction"]
        Resource = "*"
      }
    ]
  })
}

# ── Lambda function ────────────────────────────────────────────────────────────
# Package the lambda/ directory into a zip at plan time.

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "configure_instance" {
  function_name    = "${var.project_name}-configure-instance"
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Must be generous: wait for SSM agent (~2 min) + SSM command (~2 min) + buffer
  timeout = 600

  environment {
    variables = {
      PROJECT = var.project_name
    }
  }
}

# ── EventBridge rule ───────────────────────────────────────────────────────────
# ASG emits "EC2 Instance-launch Lifecycle Action" events to the default
# EventBridge bus when a lifecycle hook fires.  We filter to our specific
# ASG so other ASGs in the account are unaffected.

resource "aws_cloudwatch_event_rule" "lifecycle_launch" {
  name        = "${var.project_name}-lifecycle-launch"
  description = "Triggers Lambda when the ASG launch lifecycle hook fires"

  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = ["EC2 Instance-launch Lifecycle Action"]
    detail = {
      AutoScalingGroupName = [aws_autoscaling_group.web.name]
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.lifecycle_launch.name
  target_id = "ConfigureInstance"
  arn       = aws_lambda_function.configure_instance.arn
}

# Grant EventBridge permission to invoke Lambda
resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.configure_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lifecycle_launch.arn
}

# ── CloudWatch Alarm — CPU scale-out ──────────────────────────────────────────
# Watches the average CPU across all instances in the ASG.
# When CPU stays above the threshold for the configured evaluation periods,
# it triggers the step scaling policy.

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.cpu_alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = var.cpu_alarm_period_seconds
  statistic           = "Average"
  threshold           = var.cpu_scale_out_threshold
  alarm_description   = "Scale out when average CPU exceeds ${var.cpu_scale_out_threshold}%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.web.name
  }

  alarm_actions = [aws_autoscaling_policy.scale_out.arn]
}

# ── Scaling Policy ─────────────────────────────────────────────────────────────
# Step scaling adds 1 instance each time the alarm fires.

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${var.project_name}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.web.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"

  step_adjustment {
    scaling_adjustment          = 1
    metric_interval_lower_bound = 0
  }
}
