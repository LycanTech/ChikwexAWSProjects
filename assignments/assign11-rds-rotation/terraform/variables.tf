variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Naming prefix for all resources"
  type        = string
  default     = "chikwex"
}

variable "db_name" {
  description = "Initial database name"
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "RDS master username"
  type        = string
  default     = "admin"
}

variable "db_master_password" {
  description = "RDS initial master password (stored in Secrets Manager after creation)"
  type        = string
  sensitive   = true
}
