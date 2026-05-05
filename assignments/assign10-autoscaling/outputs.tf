output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.web.name
}

output "launch_template_id" {
  description = "ID of the Launch Template"
  value       = aws_launch_template.web.id
}

output "lifecycle_hook_name" {
  description = "Name of the ASG launch lifecycle hook"
  value       = aws_autoscaling_lifecycle_hook.launch.name
}

output "lambda_function_name" {
  description = "Name of the Lambda function that configures instances"
  value       = aws_lambda_function.configure_instance.function_name
}

output "lambda_log_group" {
  description = "CloudWatch log group for the Lambda function"
  value       = "/aws/lambda/${aws_lambda_function.configure_instance.function_name}"
}

output "cloudwatch_alarm_name" {
  description = "Name of the CPU alarm that triggers scale-out"
  value       = aws_cloudwatch_metric_alarm.cpu_high.alarm_name
}

output "ami_id" {
  description = "Amazon Linux 2023 AMI used by the Launch Template"
  value       = data.aws_ami.al2023.id
}

output "verify_commands" {
  description = "Helpful commands to verify the setup after apply"
  value       = <<-EOT
    # 1. List running instances in the ASG
    aws autoscaling describe-auto-scaling-instances \
      --query "AutoScalingInstances[?AutoScalingGroupName=='${aws_autoscaling_group.web.name}'].[InstanceId,LifecycleState,HealthStatus]" \
      --output table

    # 2. Watch Lambda logs in real time
    aws logs tail /aws/lambda/${aws_lambda_function.configure_instance.function_name} --follow

    # 3. Curl an instance's web page (replace <PUBLIC_IP>)
    curl http://<PUBLIC_IP>/

    # 4. Trigger high CPU to test scale-out (run inside an instance)
    stress --cpu 4 --timeout 300 &

    # 5. Watch ASG activity during scale-out
    aws autoscaling describe-scaling-activities \
      --auto-scaling-group-name ${aws_autoscaling_group.web.name} \
      --query "Activities[*].[StatusCode,Description]" \
      --output table
  EOT
}
