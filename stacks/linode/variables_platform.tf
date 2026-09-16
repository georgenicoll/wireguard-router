# Linode-only inputs. Everything else lives in variables_common.tf.

variable "linode_token" {
  description = "Linode API token. Prefer the LINODE_TOKEN environment variable and leave this empty."
  type        = string
  sensitive   = true
  default     = ""
}

variable "region" {
  description = "Linode region (e.g. eu-west for London, us-east for Newark)."
  type        = string
  default     = "eu-west"
}

variable "instance_type" {
  description = "Linode plan. g6-nanode-1 is the cheapest option."
  type        = string
  default     = "g6-nanode-1"
}

variable "image" {
  description = "Linode image slug."
  type        = string
  default     = "linode/ubuntu24.04"
}
