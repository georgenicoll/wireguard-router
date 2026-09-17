# ---------------------------------------------------------------------------
# AWS-specific settings. Copy this file next to your main config (the one
# WGR_CONFIG points at) and name it aws.tfvars:
#
#   cp aws.example.tfvars "$(dirname "$WGR_CONFIG")/aws.tfvars"
#
# Credentials: export AWS_PROFILE=... (or the standard AWS_* variables)
# Run with:    ./wgr aws apply
#
# architecture must match instance_type: arm64 for t4g.*, x86_64 for t3.*.
#
# Command: aws login --remote
#
# ---------------------------------------------------------------------------

aws_region    = "eu-west-2" # London
instance_type = "t4g.nano"  # cheapest current generation, arm64
architecture  = "arm64"
vpc_id        = ""          # empty = the account's default VPC
subnet_id     = ""          # empty = pick a subnet automatically
