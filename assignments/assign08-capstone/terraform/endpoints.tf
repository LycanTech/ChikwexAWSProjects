# =============================================================================
# VPC Endpoints — Private Access to AWS Services
# =============================================================================
# Without VPC endpoints, traffic to AWS services (S3, CloudWatch, etc.)
# goes over the internet. VPC endpoints keep this traffic on AWS's
# private network — faster, cheaper, and more secure.
#
# Two types:
#   Gateway Endpoint  — free, for S3 and DynamoDB, added to route tables
#   Interface Endpoint — uses ENI in your subnet, for all other services

# =============================================================================
# GATEWAY ENDPOINTS (Free — S3 and DynamoDB)
# =============================================================================

# --- S3 Gateway Endpoint (Production) ---
resource "aws_vpc_endpoint" "production_s3" {
  vpc_id       = aws_vpc.production.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.production_private.id,
    aws_route_table.production_public.id,
  ]

  tags = {
    Name = "${local.production_name}-s3-endpoint"
  }
}

# --- S3 Gateway Endpoint (Staging) ---
resource "aws_vpc_endpoint" "staging_s3" {
  vpc_id       = aws_vpc.staging.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.staging_private.id,
    aws_route_table.staging_public.id,
  ]

  tags = {
    Name = "${local.staging_name}-s3-endpoint"
  }
}

# --- S3 Gateway Endpoint (Shared Services) ---
resource "aws_vpc_endpoint" "shared_services_s3" {
  vpc_id       = aws_vpc.shared_services.id
  service_name = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.shared_services_private.id,
    aws_route_table.shared_services_public.id,
  ]

  tags = {
    Name = "${local.shared_services_name}-s3-endpoint"
  }
}

# --- DynamoDB Gateway Endpoint (Shared Services) ---
resource "aws_vpc_endpoint" "shared_services_dynamodb" {
  vpc_id       = aws_vpc.shared_services.id
  service_name = "com.amazonaws.${var.aws_region}.dynamodb"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.shared_services_private.id,
  ]

  tags = {
    Name = "${local.shared_services_name}-dynamodb-endpoint"
  }
}

# =============================================================================
# INTERFACE ENDPOINTS (for CloudWatch Logs, SSM, EC2 Messages)
# =============================================================================
# These create a private network interface (ENI) inside your subnet.
# Commonly used for:
#   - CloudWatch Logs: send logs without internet
#   - SSM (Systems Manager): manage EC2 instances without SSH/internet
#   - EC2 Messages: SSM session manager communication

# Security group for interface endpoints — allows HTTPS from VPC
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${local.shared_services_name}-vpce-"
  description = "Allow HTTPS access to VPC interface endpoints"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    description = "HTTPS from Shared Services VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.shared_services_vpc_cidr]
  }

  ingress {
    description = "HTTPS from Production VPC (via TGW)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.production_vpc_cidr]
  }

  ingress {
    description = "HTTPS from Staging VPC (via TGW)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.staging_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.shared_services_name}-vpce-sg"
  }
}

# --- CloudWatch Logs Interface Endpoint ---
resource "aws_vpc_endpoint" "shared_services_logs" {
  vpc_id              = aws_vpc.shared_services.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shared_services_private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${local.shared_services_name}-logs-endpoint"
  }
}

# --- SSM Interface Endpoint ---
resource "aws_vpc_endpoint" "shared_services_ssm" {
  vpc_id              = aws_vpc.shared_services.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shared_services_private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${local.shared_services_name}-ssm-endpoint"
  }
}

# --- EC2 Messages Interface Endpoint (needed for SSM Session Manager) ---
resource "aws_vpc_endpoint" "shared_services_ec2messages" {
  vpc_id              = aws_vpc.shared_services.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true

  subnet_ids         = aws_subnet.shared_services_private[*].id
  security_group_ids = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "${local.shared_services_name}-ec2messages-endpoint"
  }
}

# =============================================================================
# PrivateLink — Share Services Across VPCs Privately
# =============================================================================
# PrivateLink lets the Shared Services VPC expose an internal service
# (behind a Network Load Balancer) to other VPCs WITHOUT peering or TGW.
#
# How it works:
#   1. Provider VPC: creates NLB + VPC Endpoint Service
#   2. Consumer VPC: creates Interface Endpoint pointing to the service
#   Traffic stays entirely on AWS private network.

# --- Network Load Balancer in Shared Services (the "provider") ---
resource "aws_lb" "shared_service" {
  name               = "${local.prefix}-shared-nlb"
  internal           = true  # Internal only — no public access
  load_balancer_type = "network"
  subnets            = aws_subnet.shared_services_private[*].id

  tags = {
    Name = "${local.prefix}-shared-nlb"
  }
}

# NLB Target Group (placeholder — in production, you'd register actual targets)
resource "aws_lb_target_group" "shared_service" {
  name     = "${local.prefix}-shared-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.shared_services.id

  health_check {
    protocol = "TCP"
    port     = "traffic-port"
  }

  tags = {
    Name = "${local.prefix}-shared-tg"
  }
}

# NLB Listener
resource "aws_lb_listener" "shared_service" {
  load_balancer_arn = aws_lb.shared_service.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.shared_service.arn
  }
}

# --- VPC Endpoint Service (exposes the NLB via PrivateLink) ---
resource "aws_vpc_endpoint_service" "shared_service" {
  acceptance_required        = false  # Auto-accept connections (set true in prod)
  network_load_balancer_arns = [aws_lb.shared_service.arn]

  tags = {
    Name = "${local.prefix}-shared-endpoint-service"
  }
}

# --- Production VPC consumes the shared service via PrivateLink ---
resource "aws_security_group" "privatelink_consumer" {
  name_prefix = "${local.production_name}-privatelink-"
  description = "Allow access to PrivateLink shared service"
  vpc_id      = aws_vpc.production.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.production_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.production_name}-privatelink-sg"
  }
}

resource "aws_vpc_endpoint" "production_shared_service" {
  vpc_id              = aws_vpc.production.id
  service_name        = aws_vpc_endpoint_service.shared_service.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = false

  subnet_ids         = aws_subnet.production_private[*].id
  security_group_ids = [aws_security_group.privatelink_consumer.id]

  tags = {
    Name = "${local.production_name}-shared-service-endpoint"
  }
}
