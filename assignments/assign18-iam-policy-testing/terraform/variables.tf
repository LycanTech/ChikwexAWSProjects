variable "aws_region" {
  description = "Primary AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "chikwex-assign18"
}

variable "dev_vpc_id" {
  description = "VPC ID where developer is allowed to create/delete resources"
  type        = string
  default     = "vpc-0xxxxxxxxxxxxxxxx"
}

variable "alert_email" {
  description = "Email for Access Analyzer findings notifications"
  type        = string
  default     = "cheekway18@gmail.com"
}
