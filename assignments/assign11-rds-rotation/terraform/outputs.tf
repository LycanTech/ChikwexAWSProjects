output "rds_endpoint" {
  description = "RDS instance endpoint"
  value       = aws_db_instance.main.address
}

output "rds_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.main.identifier
}

output "secret_arn" {
  description = "Secrets Manager secret ARN"
  value       = aws_secretsmanager_secret.rds.arn
}

output "rotation_lambda_arn" {
  description = "Rotation Lambda ARN"
  value       = aws_lambda_function.rotation.arn
}

output "app_lambda_arn" {
  description = "App Lambda ARN"
  value       = aws_lambda_function.app.arn
}
