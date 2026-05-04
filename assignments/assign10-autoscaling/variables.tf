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

variable "instance_type" {
  description = "EC2 instance type for the ASG"
  type        = string
  default     = "t3.micro"
}

# ── ASG sizing ────────────────────────────────────────────────────────────────

variable "asg_min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "asg_max_size" {
  description = "Maximum number of instances the ASG can scale to"
  type        = number
  default     = 3
}

variable "asg_desired_capacity" {
  description = "Initial desired instance count"
  type        = number
  default     = 1
}

# ── Scaling alarm ─────────────────────────────────────────────────────────────

variable "cpu_scale_out_threshold" {
  description = "CPU utilisation (%) that triggers scale-out"
  type        = number
  default     = 60
}

variable "cpu_alarm_period_seconds" {
  description = "CloudWatch evaluation period in seconds"
  type        = number
  default     = 120
}

variable "cpu_alarm_evaluation_periods" {
  description = "Number of consecutive periods above threshold before alarming"
  type        = number
  default     = 2
}

# ── Lifecycle hook ────────────────────────────────────────────────────────────

variable "lifecycle_heartbeat_timeout" {
  description = "Seconds the lifecycle hook waits before timing out (must exceed Lambda runtime)"
  type        = number
  default     = 600
}
