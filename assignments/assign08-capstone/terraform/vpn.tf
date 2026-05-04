# =============================================================================
# Site-to-Site VPN — On-Premises Connectivity
# =============================================================================
# A Site-to-Site VPN creates an encrypted IPsec tunnel between your
# corporate data center and AWS over the public internet.
#
# Components:
#   Customer Gateway (CGW) — represents the on-prem router/firewall
#   VPN Connection — the encrypted tunnel itself (2 tunnels for redundancy)
#   Transit Gateway — AWS side endpoint (we attach VPN to our existing TGW)
#
# In production, you'd use your real router's public IP. Here we use a
# placeholder IP to demonstrate the configuration.

# --- Customer Gateway ---
# This represents the on-premises VPN device (router/firewall).
# The IP address would be your real device's public IP in production.
resource "aws_customer_gateway" "onprem" {
  bgp_asn    = 65000             # BGP Autonomous System Number for on-prem
  ip_address = "203.0.113.1"     # Placeholder — replace with real device IP
  type       = "ipsec.1"         # IPsec is the only supported type

  tags = {
    Name = "${local.prefix}-onprem-cgw"
  }
}

# --- VPN Connection (attached to Transit Gateway) ---
# By attaching to the TGW instead of a VPN Gateway, on-prem traffic
# can reach ALL VPCs through the Transit Gateway hub.
resource "aws_vpn_connection" "onprem" {
  customer_gateway_id = aws_customer_gateway.onprem.id
  transit_gateway_id  = aws_ec2_transit_gateway.main.id
  type                = "ipsec.1"
  static_routes_only  = true  # Using static routes (simpler than BGP for lab)

  tags = {
    Name = "${local.prefix}-onprem-vpn"
  }
}

# --- TGW Route Table for VPN ---
# The VPN gets its own route table on the Transit Gateway
resource "aws_ec2_transit_gateway_route_table" "vpn" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id

  tags = {
    Name = "${local.prefix}-vpn-tgw-rt"
  }
}

# --- Static route on TGW pointing on-prem CIDR to VPN attachment ---
# This tells the TGW: "to reach 192.168.0.0/16, send traffic through the VPN"
resource "aws_ec2_transit_gateway_route" "to_onprem" {
  destination_cidr_block         = var.onprem_cidr
  transit_gateway_attachment_id  = aws_vpn_connection.onprem.transit_gateway_attachment_id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.shared_services.id
}

# --- VPC routes to on-premises via TGW ---
# Each VPC's private route table gets a route to on-prem through the TGW
resource "aws_route" "production_to_onprem" {
  route_table_id         = aws_route_table.production_private.id
  destination_cidr_block = var.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "staging_to_onprem" {
  route_table_id         = aws_route_table.staging_private.id
  destination_cidr_block = var.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}

resource "aws_route" "shared_to_onprem" {
  route_table_id         = aws_route_table.shared_services_private.id
  destination_cidr_block = var.onprem_cidr
  transit_gateway_id     = aws_ec2_transit_gateway.main.id
}
