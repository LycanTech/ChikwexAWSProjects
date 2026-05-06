variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "chikwex-assign17"
}

variable "alert_email" {
  description = "Email address for DLQ SNS alerts"
  type        = string
  default     = "cheekway18@gmail.com"
}

variable "fail_rate" {
  description = "Consumer Lambda failure rate (0.0 – 1.0)"
  type        = string
  default     = "0.20"
}
