terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = var.tags
  }

  # The provider silently retries transient EC2 errors, including
  # InsufficientInstanceCapacity, with backoff - by default for long enough
  # that a capacity shortage looks like a hang rather than an error. Fail
  # fast instead; retry manually (destroy and re-apply to try a different
  # AZ - see modules/platform/aws/main.tf).
  max_retries = 3
}
