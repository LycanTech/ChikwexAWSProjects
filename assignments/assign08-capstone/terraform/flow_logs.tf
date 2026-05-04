# =============================================================================
# VPC Flow Logs — Traffic Metadata Capture
# =============================================================================
# Flow Logs record metadata about IP traffic flowing through your VPC:
#   - Source/destination IP and port
#   - Protocol, action (ACCEPT/REJECT), bytes transferred
#   - NOT the packet contents (for that, use Traffic Mirroring)
#
# We send flow logs to both CloudWatch (real-time alerts) and S3 (long-term
# analysis with Athena).

# --- IAM Role for Flow Logs ---
# Flow Logs need permission to write to CloudWatch Logs
resource "aws_iam_role" "flow_logs" {
  name = "${local.prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })

  tags = {
    Name = "${local.prefix}-flow-logs-role"
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.prefix}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}

# --- CloudWatch Log Groups for Flow Logs ---
resource "aws_cloudwatch_log_group" "flow_logs_production" {
  name              = "/aws/vpc/flow-logs/${local.production_name}"
  retention_in_days = 30

  tags = {
    Name = "${local.production_name}-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs_staging" {
  name              = "/aws/vpc/flow-logs/${local.staging_name}"
  retention_in_days = 30

  tags = {
    Name = "${local.staging_name}-flow-logs"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs_shared" {
  name              = "/aws/vpc/flow-logs/${local.shared_services_name}"
  retention_in_days = 30

  tags = {
    Name = "${local.shared_services_name}-flow-logs"
  }
}

# --- S3 Bucket for Flow Logs (for Athena analysis) ---
resource "aws_s3_bucket" "flow_logs" {
  bucket_prefix = "${local.prefix}-flow-logs-"
  force_destroy = true  # Lab only — allows deletion even with contents

  tags = {
    Name = "${local.prefix}-flow-logs-bucket"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- Enable Flow Logs on all 3 VPCs ---
# CloudWatch destination (real-time monitoring)
resource "aws_flow_log" "production_cw" {
  vpc_id          = aws_vpc.production.id
  traffic_type    = "ALL"  # Capture ACCEPT and REJECT
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs_production.arn

  tags = {
    Name = "${local.production_name}-flow-log-cw"
  }
}

resource "aws_flow_log" "staging_cw" {
  vpc_id          = aws_vpc.staging.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs_staging.arn

  tags = {
    Name = "${local.staging_name}-flow-log-cw"
  }
}

resource "aws_flow_log" "shared_cw" {
  vpc_id          = aws_vpc.shared_services.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs_shared.arn

  tags = {
    Name = "${local.shared_services_name}-flow-log-cw"
  }
}

# S3 destination (long-term storage for Athena queries)
resource "aws_flow_log" "production_s3" {
  vpc_id               = aws_vpc.production.id
  traffic_type         = "ALL"
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"

  tags = {
    Name = "${local.production_name}-flow-log-s3"
  }
}

resource "aws_flow_log" "staging_s3" {
  vpc_id               = aws_vpc.staging.id
  traffic_type         = "ALL"
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"

  tags = {
    Name = "${local.staging_name}-flow-log-s3"
  }
}

resource "aws_flow_log" "shared_s3" {
  vpc_id               = aws_vpc.shared_services.id
  traffic_type         = "ALL"
  log_destination      = aws_s3_bucket.flow_logs.arn
  log_destination_type = "s3"

  tags = {
    Name = "${local.shared_services_name}-flow-log-s3"
  }
}

# =============================================================================
# Traffic Mirroring — Full Packet Capture for Inspection
# =============================================================================
# Traffic Mirroring copies actual network packets for deep inspection.
# Use cases: IDS/IPS, forensics, compliance auditing.
#
# Components:
#   Mirror Target — where copied packets go (an ENI or NLB)
#   Mirror Filter — which traffic to copy (by protocol, port, direction)
#   Mirror Session — links source ENI → filter → target

# --- Mirror Target (NLB for IDS/IPS inspection) ---
resource "aws_lb" "mirror_target" {
  name               = "${local.prefix}-mirror-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = aws_subnet.shared_services_private[*].id

  tags = {
    Name = "${local.prefix}-mirror-target-nlb"
  }
}

resource "aws_ec2_traffic_mirror_target" "inspection" {
  description               = "Traffic mirror target for packet inspection"
  network_load_balancer_arn = aws_lb.mirror_target.arn

  tags = {
    Name = "${local.prefix}-mirror-target"
  }
}

# --- Mirror Filter (capture HTTP and HTTPS traffic) ---
resource "aws_ec2_traffic_mirror_filter" "inspection" {
  description = "Capture HTTP/HTTPS traffic for inspection"

  tags = {
    Name = "${local.prefix}-mirror-filter"
  }
}

# Capture inbound HTTP
resource "aws_ec2_traffic_mirror_filter_rule" "http_inbound" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.inspection.id
  description              = "Capture inbound HTTP"
  rule_number              = 100
  rule_action              = "accept"
  traffic_direction        = "ingress"
  protocol                 = 6  # TCP

  destination_port_range {
    from_port = 80
    to_port   = 80
  }

  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

# Capture inbound HTTPS
resource "aws_ec2_traffic_mirror_filter_rule" "https_inbound" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.inspection.id
  description              = "Capture inbound HTTPS"
  rule_number              = 110
  rule_action              = "accept"
  traffic_direction        = "ingress"
  protocol                 = 6

  destination_port_range {
    from_port = 443
    to_port   = 443
  }

  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

# Capture outbound HTTP
resource "aws_ec2_traffic_mirror_filter_rule" "http_outbound" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.inspection.id
  description              = "Capture outbound HTTP"
  rule_number              = 100
  rule_action              = "accept"
  traffic_direction        = "egress"
  protocol                 = 6

  source_port_range {
    from_port = 80
    to_port   = 80
  }

  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

# Capture outbound HTTPS
resource "aws_ec2_traffic_mirror_filter_rule" "https_outbound" {
  traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.inspection.id
  description              = "Capture outbound HTTPS"
  rule_number              = 110
  rule_action              = "accept"
  traffic_direction        = "egress"
  protocol                 = 6

  source_port_range {
    from_port = 443
    to_port   = 443
  }

  source_cidr_block      = "0.0.0.0/0"
  destination_cidr_block = "0.0.0.0/0"
}

# NOTE: Mirror Sessions require a specific source ENI (network interface).
# In a real deployment, you'd create a mirror session for each EC2 instance
# you want to inspect. Example (commented out — needs a real ENI ID):
#
# resource "aws_ec2_traffic_mirror_session" "example" {
#   description              = "Mirror production web server traffic"
#   network_interface_id     = aws_instance.web_server.primary_network_interface_id
#   traffic_mirror_filter_id = aws_ec2_traffic_mirror_filter.inspection.id
#   traffic_mirror_target_id = aws_ec2_traffic_mirror_target.inspection.id
#   session_number           = 1
# }
