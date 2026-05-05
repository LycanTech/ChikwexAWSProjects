output "sns_topic_arn" {
  description = "ARN of the SNS notification topic"
  value       = aws_sns_topic.notifications.arn
}

output "ec2_scheduler_lambda_arn" {
  description = "ARN of the EC2 scheduler Lambda"
  value       = aws_lambda_function.ec2_scheduler.arn
}

output "snapshot_cleanup_lambda_arn" {
  description = "ARN of the snapshot cleanup Lambda"
  value       = aws_lambda_function.snapshot_cleanup.arn
}

output "security_check_lambda_arn" {
  description = "ARN of the security check Lambda"
  value       = aws_lambda_function.security_check.arn
}

output "ec2_scheduler_rule_arn" {
  description = "ARN of the EC2 scheduler EventBridge rule"
  value       = aws_cloudwatch_event_rule.ec2_scheduler.arn
}

output "snapshot_cleanup_rule_arn" {
  description = "ARN of the snapshot cleanup EventBridge rule"
  value       = aws_cloudwatch_event_rule.snapshot_cleanup.arn
}

output "security_check_rule_arn" {
  description = "ARN of the security check EventBridge rule"
  value       = aws_cloudwatch_event_rule.security_check.arn
}
