variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "chikwex-assign16"
}

variable "object_prefix" {
  description = "S3 key prefix where the 1000 seed objects are stored"
  type        = string
  default     = "data/"
}
