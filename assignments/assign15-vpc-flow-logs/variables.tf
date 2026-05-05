variable "aws_region" {
  description = "AWS region to deploy resources in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names"
  type        = string
  default     = "vpcflow-assign15"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.15.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.15.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.15.2.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for both lab instances"
  type        = string
  default     = "t3.micro"
}

variable "ec2_public_key" {
  description = "SSH public key material to create the EC2 key pair"
  type        = string
  # Generate with: ssh-keygen -t rsa -b 4096 -f assign15-key
  # Then paste the content of assign15-key.pub here or pass via -var
}

variable "operator_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 1.2.3.4/32) – used to allow SSH to the public EC2"
  type        = string
  # Find yours with: curl -s https://checkip.amazonaws.com
}

# VPC Flow Log custom format – extended fields enable richer Athena queries.
# The field order must match the Athena table column order in main.tf.
variable "flow_log_format" {
  description = "VPC Flow Log record format string"
  type        = string
  default     = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id} $${pkt-src-aws-service} $${pkt-dst-aws-service} $${flow-direction} $${traffic-path}"
}
