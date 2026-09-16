# AWS-only inputs. Credentials come from the usual AWS SDK sources
# (AWS_PROFILE, environment variables, or an instance role).

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "instance_type" {
  description = "t4g.nano (arm64) is the cheapest current-generation instance."
  type        = string
  default     = "t4g.nano"
}

variable "architecture" {
  description = "Must match instance_type: arm64 for t4g.*, x86_64 for t3.*."
  type        = string
  default     = "arm64"
}

variable "vpc_id" {
  description = "Leave empty to use the account's default VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Leave empty to pick a subnet from the chosen VPC automatically."
  type        = string
  default     = ""
}
