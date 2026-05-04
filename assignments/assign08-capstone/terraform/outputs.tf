# =============================================================================
# Outputs — Key resource IDs and information
# =============================================================================
# Outputs display important values after terraform apply.
# Useful for referencing resources or passing values to other tools.

output "production_vpc_id" {
  description = "Production VPC ID"
  value       = aws_vpc.production.id
}

output "staging_vpc_id" {
  description = "Staging VPC ID"
  value       = aws_vpc.staging.id
}

output "shared_services_vpc_id" {
  description = "Shared Services VPC ID"
  value       = aws_vpc.shared_services.id
}

output "transit_gateway_id" {
  description = "Transit Gateway ID"
  value       = aws_ec2_transit_gateway.main.id
}

output "vpn_connection_id" {
  description = "Site-to-Site VPN Connection ID"
  value       = aws_vpn_connection.onprem.id
}

output "network_firewall_arn" {
  description = "Production Network Firewall ARN"
  value       = aws_networkfirewall_firewall.production.arn
}

output "flow_logs_s3_bucket" {
  description = "S3 bucket for VPC Flow Logs (Athena queries)"
  value       = aws_s3_bucket.flow_logs.id
}

output "sns_security_alerts_topic" {
  description = "SNS topic ARN for security alerts"
  value       = aws_sns_topic.security_alerts.arn
}

output "privatelink_service_name" {
  description = "PrivateLink endpoint service name"
  value       = aws_vpc_endpoint_service.shared_service.service_name
}
