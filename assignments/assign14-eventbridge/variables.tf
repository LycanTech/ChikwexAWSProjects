variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to every resource name"
  type        = string
  default     = "chikwex"
}

variable "alert_email" {
  description = "Email address that receives SNS notifications"
  type        = string
  default     = "chikwe.azinge@techconsulting.tech"
}

variable "snapshot_retention_days" {
  description = "Snapshots older than this (days) and without tags will be deleted"
  type        = number
  default     = 30
}
