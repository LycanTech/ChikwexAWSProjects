output "developer_user_arn" {
  description = "ARN of the developer-test IAM user"
  value       = aws_iam_user.developer_test.arn
}

output "developer_role_arn" {
  description = "ARN of the developer role (for assume-role tests)"
  value       = aws_iam_role.developer_role.arn
}

output "developer_policy_arn" {
  description = "ARN of the custom developer policy"
  value       = aws_iam_policy.developer_policy.arn
}

output "permission_boundary_arn" {
  description = "ARN of the permission boundary policy"
  value       = aws_iam_policy.permission_boundary.arn
}

output "access_analyzer_arn" {
  description = "ARN of the IAM Access Analyzer"
  value       = aws_accessanalyzer_analyzer.account_analyzer.arn
}

output "access_key_id" {
  description = "Access key ID for developer-test (use in scripts)"
  value       = aws_iam_access_key.developer_test.id
  sensitive   = true
}

output "secret_access_key" {
  description = "Secret access key for developer-test"
  value       = aws_iam_access_key.developer_test.secret
  sensitive   = true
}

output "sns_topic_arn" {
  description = "SNS topic for Access Analyzer findings alerts"
  value       = aws_sns_topic.analyzer_alerts.arn
}
