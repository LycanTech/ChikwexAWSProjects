# =============================================================================
# Provider Configuration
# =============================================================================
# Terraform requires a "provider" to interact with cloud APIs.
# The AWS provider lets Terraform create/manage AWS resources.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "${var.prefix}-CapStone8-NetworkSecurity"
      Prefix      = var.prefix
      Environment = "lab"
      ManagedBy   = "terraform"
    }
  }
}
