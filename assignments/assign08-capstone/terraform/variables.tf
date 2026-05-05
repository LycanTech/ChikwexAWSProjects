# =============================================================================
# Variables
# =============================================================================
# Variables make our Terraform code reusable and configurable.
# Instead of hardcoding values, we define them here and reference them
# throughout our code with var.<name>.

variable "prefix" {
  description = "Prefix for all resource names to identify project resources"
  type        = string
  default     = "chikwex"
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# --- VPC CIDR Blocks ---
# Each VPC needs a unique, non-overlapping CIDR range.
# /16 gives us 65,536 IPs per VPC — plenty of room for subnets.

variable "production_vpc_cidr" {
  description = "CIDR block for the Production VPC"
  type        = string
  default     = "10.1.0.0/16"
}

variable "staging_vpc_cidr" {
  description = "CIDR block for the Staging VPC"
  type        = string
  default     = "10.2.0.0/16"
}

variable "shared_services_vpc_cidr" {
  description = "CIDR block for the Shared Services VPC"
  type        = string
  default     = "10.3.0.0/16"
}

# --- Subnet CIDR Blocks ---
# We split each VPC into public and private subnets across 2 AZs.
# Public subnets: resources that need internet access (load balancers, NAT gateways)
# Private subnets: resources that should NOT be directly accessible from the internet

variable "production_public_subnets" {
  description = "Public subnet CIDRs for Production VPC"
  type        = list(string)
  default     = ["10.1.1.0/24", "10.1.2.0/24"]
}

variable "production_private_subnets" {
  description = "Private subnet CIDRs for Production VPC"
  type        = list(string)
  default     = ["10.1.10.0/24", "10.1.20.0/24"]
}

variable "staging_public_subnets" {
  description = "Public subnet CIDRs for Staging VPC"
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]
}

variable "staging_private_subnets" {
  description = "Private subnet CIDRs for Staging VPC"
  type        = list(string)
  default     = ["10.2.10.0/24", "10.2.20.0/24"]
}

variable "shared_services_public_subnets" {
  description = "Public subnet CIDRs for Shared Services VPC"
  type        = list(string)
  default     = ["10.3.1.0/24", "10.3.2.0/24"]
}

variable "shared_services_private_subnets" {
  description = "Private subnet CIDRs for Shared Services VPC"
  type        = list(string)
  default     = ["10.3.10.0/24", "10.3.20.0/24"]
}

# --- Availability Zones ---
variable "availability_zones" {
  description = "AZs to deploy subnets into (2 for high availability)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# --- On-Premises Simulation ---
variable "onprem_cidr" {
  description = "Simulated on-premises network CIDR"
  type        = string
  default     = "192.168.0.0/16"
}
