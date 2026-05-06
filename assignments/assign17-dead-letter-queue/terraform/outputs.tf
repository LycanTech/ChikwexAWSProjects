output "main_queue_url" {
  description = "Standard SQS main queue URL"
  value       = aws_sqs_queue.main.url
}

output "main_queue_arn" {
  value = aws_sqs_queue.main.arn
}

output "dlq_url" {
  description = "Dead Letter Queue URL"
  value       = aws_sqs_queue.dlq.url
}

output "dlq_arn" {
  value = aws_sqs_queue.dlq.arn
}

output "fifo_main_queue_url" {
  description = "FIFO main queue URL"
  value       = aws_sqs_queue.fifo_main.url
}

output "fifo_dlq_url" {
  description = "FIFO Dead Letter Queue URL"
  value       = aws_sqs_queue.fifo_dlq.url
}

output "sns_topic_arn" {
  description = "SNS topic ARN for DLQ alerts"
  value       = aws_sns_topic.dlq_alerts.arn
}

output "consumer_lambda" {
  value = aws_lambda_function.consumer.function_name
}

output "dlq_monitor_lambda" {
  value = aws_lambda_function.dlq_monitor.function_name
}

output "send_command" {
  description = "Command to send 100 test messages"
  value       = "python scripts/send_messages.py --queue-url ${aws_sqs_queue.main.url} --count 100"
}

output "replay_command" {
  description = "Command to replay failed messages from DLQ"
  value       = "python scripts/replay.py --dlq-url ${aws_sqs_queue.dlq.url} --target-url ${aws_sqs_queue.main.url}"
}
