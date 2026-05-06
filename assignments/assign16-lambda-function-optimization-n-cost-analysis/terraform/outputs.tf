output "s3_bucket" {
  description = "S3 bucket holding the 1000 seed objects"
  value       = aws_s3_bucket.data.bucket
}

output "dynamodb_table" {
  description = "DynamoDB table receiving processed results"
  value       = aws_dynamodb_table.results.name
}

output "lambda_v1_name" {
  description = "Unoptimized Lambda function name"
  value       = aws_lambda_function.v1.function_name
}

output "lambda_v2_name" {
  description = "Optimized Lambda function name"
  value       = aws_lambda_function.v2.function_name
}

output "lambda_v1_arn" {
  value = aws_lambda_function.v1.arn
}

output "lambda_v2_arn" {
  value = aws_lambda_function.v2.arn
}

output "xray_console" {
  description = "X-Ray service map for both functions"
  value       = "https://${var.aws_region}.console.aws.amazon.com/xray/home?region=${var.aws_region}#/service-map"
}

output "seed_command" {
  description = "Command to seed S3 with 1000 objects after apply"
  value       = "python scripts/seed_s3.py --bucket ${aws_s3_bucket.data.bucket} --prefix data/ --count 1000"
}
