# =============================================================================
# Security — Layered Defense (Security Groups, NACLs, Network Firewall)
# =============================================================================
# Defense in depth means multiple security layers. If one layer is
# misconfigured, others still protect your resources.

# =============================================================================
# SECURITY GROUPS — Instance-Level (Layer 1)
# =============================================================================
# Security Groups are STATEFUL firewalls attached to ENIs (network interfaces).
# "Stateful" means if you allow inbound traffic, the response is auto-allowed.

# --- Production Web Server Security Group ---
resource "aws_security_group" "production_web" {
  name_prefix = "${local.production_name}-web-"
  description = "Allow HTTP/HTTPS inbound, all outbound"
  vpc_id      = aws_vpc.production.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.production_name}-web-sg"
  }
}

# --- Production App Server Security Group ---
resource "aws_security_group" "production_app" {
  name_prefix = "${local.production_name}-app-"
  description = "Allow traffic only from web tier"
  vpc_id      = aws_vpc.production.id

  ingress {
    description     = "App port from web servers only"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.production_web.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.production_name}-app-sg"
  }
}

# --- Production Database Security Group ---
resource "aws_security_group" "production_db" {
  name_prefix = "${local.production_name}-db-"
  description = "Allow traffic only from app tier"
  vpc_id      = aws_vpc.production.id

  ingress {
    description     = "MySQL from app servers only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.production_app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.production_name}-db-sg"
  }
}

# --- Shared Services Bastion Security Group ---
resource "aws_security_group" "bastion" {
  name_prefix = "${local.shared_services_name}-bastion-"
  description = "SSH access for bastion host"
  vpc_id      = aws_vpc.shared_services.id

  ingress {
    description = "SSH from on-premises"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.onprem_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.shared_services_name}-bastion-sg"
  }
}

# =============================================================================
# NETWORK ACLs — Subnet-Level (Layer 2)
# =============================================================================
# NACLs are STATELESS — you must explicitly allow BOTH inbound AND outbound.
# They are evaluated in rule-number order (lowest first). Default NACL allows all.
# Custom NACLs deny all by default, so we add explicit allow rules.

# --- Production Private Subnet NACL ---
resource "aws_network_acl" "production_private" {
  vpc_id     = aws_vpc.production.id
  subnet_ids = aws_subnet.production_private[*].id

  # Allow inbound from within the VPC
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.production_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  # Allow inbound from Shared Services (via TGW)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.shared_services_vpc_cidr
    from_port  = 0
    to_port    = 65535
  }

  # Allow inbound from on-premises
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = var.onprem_cidr
    from_port  = 0
    to_port    = 65535
  }

  # Allow ephemeral ports inbound (return traffic from internet via NAT)
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${local.production_name}-private-nacl"
  }
}

# --- Production Public Subnet NACL ---
resource "aws_network_acl" "production_public" {
  vpc_id     = aws_vpc.production.id
  subnet_ids = aws_subnet.production_public[*].id

  # Allow HTTP inbound
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow HTTPS inbound
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow ephemeral ports inbound (return traffic)
  ingress {
    rule_no    = 200
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Allow all outbound
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "${local.production_name}-public-nacl"
  }
}

# =============================================================================
# AWS NETWORK FIREWALL — VPC-Level Deep Packet Inspection (Layer 3)
# =============================================================================
# Network Firewall provides stateful inspection, intrusion prevention,
# and domain filtering. It inspects ALL traffic entering/leaving the VPC.
#
# We deploy it in the Production VPC for maximum protection of live workloads.
# It needs its own subnet to operate.

# --- Firewall Subnet (dedicated subnet for the firewall endpoints) ---
resource "aws_subnet" "production_firewall" {
  count             = length(var.availability_zones)
  vpc_id            = aws_vpc.production.id
  cidr_block        = cidrsubnet(var.production_vpc_cidr, 12, 240 + count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "${local.production_name}-firewall-${var.availability_zones[count.index]}"
    Tier = "firewall"
  }
}

# --- Firewall Rule Group (stateful rules) ---
resource "aws_networkfirewall_rule_group" "production" {
  capacity = 100
  name     = "${local.prefix}-production-rules"
  type     = "STATEFUL"

  rule_group {
    rules_source {
      # Suricata-compatible rules for deep packet inspection
      rules_string = <<-EOT
        # Block known malicious domains
        drop tls any any -> any any (msg:"Block malicious domain"; tls.sni; content:"malware-c2.example.com"; sid:1000001; rev:1;)

        # Allow HTTPS outbound
        pass tls any any -> any 443 (msg:"Allow HTTPS outbound"; flow:to_server; sid:1000002; rev:1;)

        # Allow HTTP outbound
        pass tcp any any -> any 80 (msg:"Allow HTTP outbound"; flow:to_server; sid:1000003; rev:1;)

        # Allow DNS
        pass udp any any -> any 53 (msg:"Allow DNS"; sid:1000004; rev:1;)
        pass tcp any any -> any 53 (msg:"Allow DNS TCP"; sid:1000005; rev:1;)
      EOT
    }
  }

  tags = {
    Name = "${local.prefix}-production-fw-rules"
  }
}

# --- Firewall Policy ---
resource "aws_networkfirewall_firewall_policy" "production" {
  name = "${local.prefix}-production-fw-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.production.arn
    }
  }

  tags = {
    Name = "${local.prefix}-production-fw-policy"
  }
}

# --- Network Firewall ---
resource "aws_networkfirewall_firewall" "production" {
  name                = "${local.prefix}-production-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.production.arn
  vpc_id              = aws_vpc.production.id

  dynamic "subnet_mapping" {
    for_each = aws_subnet.production_firewall
    content {
      subnet_id = subnet_mapping.value.id
    }
  }

  tags = {
    Name = "${local.prefix}-production-firewall"
  }
}

# --- Network Firewall Logging ---
resource "aws_cloudwatch_log_group" "firewall_alert" {
  name              = "/aws/network-firewall/${local.prefix}-production/alert"
  retention_in_days = 30

  tags = {
    Name = "${local.prefix}-firewall-alert-logs"
  }
}

resource "aws_cloudwatch_log_group" "firewall_flow" {
  name              = "/aws/network-firewall/${local.prefix}-production/flow"
  retention_in_days = 30

  tags = {
    Name = "${local.prefix}-firewall-flow-logs"
  }
}

resource "aws_networkfirewall_logging_configuration" "production" {
  firewall_arn = aws_networkfirewall_firewall.production.arn

  logging_configuration {
    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_alert.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "ALERT"
    }

    log_destination_config {
      log_destination = {
        logGroup = aws_cloudwatch_log_group.firewall_flow.name
      }
      log_destination_type = "CloudWatchLogs"
      log_type             = "FLOW"
    }
  }
}
