output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_ec2_public_ip" {
  description = "Public IP of the public EC2 instance – use this to SSH in"
  value       = aws_instance.public.public_ip
}

output "public_ec2_private_ip" {
  description = "Private IP of the public EC2 instance"
  value       = aws_instance.public.private_ip
}

output "private_ec2_private_ip" {
  description = "Private IP of the private EC2 instance – target for internal traffic tests"
  value       = aws_instance.private.private_ip
}

output "flow_logs_bucket" {
  description = "S3 bucket name receiving VPC Flow Logs"
  value       = aws_s3_bucket.flow_logs.bucket
}

output "athena_database" {
  description = "Athena database name"
  value       = aws_athena_database.flow_logs.name
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = aws_athena_workgroup.flow_logs.name
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.bucket
}

output "ssh_command" {
  description = "Command to SSH into the public instance"
  value       = "ssh -i assign15-key ec2-user@${aws_instance.public.public_ip}"
}

output "athena_setup_instructions" {
  description = "Steps to finish Athena setup after apply"
  value       = <<-MSG
    1. Open Athena Console → Workgroup: ${aws_athena_workgroup.flow_logs.name}
    2. Run the saved query '${local.prefix}-create-flow-logs-table' to create the table.
    3. Wait ~10 min for the first flow log files to appear in S3.
    4. Run the other saved queries from the named queries list.
    5. Cost estimate: Athena charges $5 per TB scanned.
       Parquet compression typically achieves 10-20x reduction vs plain text.
  MSG
}
