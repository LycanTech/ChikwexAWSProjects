# =============================================================================
# Transit Gateway — Central Hub for Inter-VPC Communication
# =============================================================================
# Transit Gateway (TGW) acts as a cloud router connecting all our VPCs.
# Instead of creating individual peering connections between each pair,
# every VPC attaches to the TGW and routes traffic through it.
#
# Architecture:
#   Production VPC ──┐
#   Staging VPC ─────┼── Transit Gateway ── (all can talk to each other)
#   Shared Services ─┘

resource "aws_ec2_transit_gateway" "main" {
  description                     = "Central hub connecting all VPCs"
  default_route_table_association = "disable"  # We'll manage route tables manually
  default_route_table_propagation = "disable"  # for fine-grained control
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"   # Equal-cost multi-path for VPN

  tags = {
    Name = "${local.prefix}-transit-gateway"
  }
}

# =============================================================================
# TGW Attachments — Connect each VPC to the Transit Gateway
# =============================================================================
# An "attachment" is the link between a VPC and the TGW.
# We attach via the private subnets (best practice — keeps TGW traffic internal).

resource "aws_ec2_transit_gateway_vpc_attachment" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.production.id
  subnet_ids         = aws_subnet.production_private[*].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.production_name}-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "staging" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.staging.id
  subnet_ids         = aws_subnet.staging_private[*].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.staging_name}-tgw-attachment"
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.shared_services.id
  subnet_ids         = aws_subnet.shared_services_private[*].id

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = {
    Name = "${local.shared_services_name}-tgw-attachment"
  }
}

# =============================================================================
# TGW Route Tables — Control which VPCs can talk to each other
# =============================================================================
# We create separate route tables for different traffic policies:
#   - Production RT: prod can reach shared-services (but NOT staging directly)
#   - Staging RT: staging can reach shared-services (but NOT production)
#   - Shared Services RT: can reach both prod and staging (hub)
#
# This is a security best practice — staging should never directly
# access production resources.

resource "aws_ec2_transit_gateway_route_table" "production" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${local.production_name}-tgw-rt"
  }
}

resource "aws_ec2_transit_gateway_route_table" "staging" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${local.staging_name}-tgw-rt"
  }
}

resource "aws_ec2_transit_gateway_route_table" "shared_services" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${local.shared_services_name}-tgw-rt"
  }
}

# --- Associate attachments with their route tables ---
resource "aws_ec2_transit_gateway_route_table_association" "production" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

resource "aws_ec2_transit_gateway_route_table_association" "staging" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.staging.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.staging.id
}

resource "aws_ec2_transit_gateway_route_table_association" "shared_services" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# --- Route Propagation ---
# "Propagation" automatically adds routes for attached VPCs.
# Production and Staging propagate to Shared Services (so it can reach them).
# Shared Services propagates to Production and Staging (so they can reach it).

# Shared Services can reach Production
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_prod" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.production.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# Shared Services can reach Staging
resource "aws_ec2_transit_gateway_route_table_propagation" "shared_to_staging" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.staging.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# Production can reach Shared Services
resource "aws_ec2_transit_gateway_route_table_propagation" "prod_to_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.production.id
}

# Staging can reach Shared Services
resource "aws_ec2_transit_gateway_route_table_propagation" "staging_to_shared" {
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.shared_services.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.staging.id
}

# =============================================================================
# VPC Route Table Updates — Tell VPCs to use the TGW for cross-VPC traffic
# =============================================================================
# Each VPC's private route table needs routes pointing to other VPC CIDRs
# via the Transit Gateway.

# Production private routes → Staging and Shared Services via TGW
resource "aws_route" "production_to_staging" {
  route_table_id         = aws_route_table.production_private.id
  destination_cidr_block = var.staging_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "production_to_shared" {
  route_table_id         = aws_route_table.production_private.id
  destination_cidr_block = var.shared_services_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

# Staging private routes → Production and Shared Services via TGW
resource "aws_route" "staging_to_production" {
  route_table_id         = aws_route_table.staging_private.id
  destination_cidr_block = var.production_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "staging_to_shared" {
  route_table_id         = aws_route_table.staging_private.id
  destination_cidr_block = var.shared_services_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

# Shared Services private routes → Production and Staging via TGW
resource "aws_route" "shared_to_production" {
  route_table_id         = aws_route_table.shared_services_private.id
  destination_cidr_block = var.production_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "shared_to_staging" {
  route_table_id         = aws_route_table.shared_services_private.id
  destination_cidr_block = var.staging_vpc_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
