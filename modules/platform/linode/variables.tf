# Standard platform-module interface. Every module under modules/platform/*
# accepts these same inputs, which is what makes swapping clouds cheap.

variable "node_name" { type = string }

variable "user_data" {
  description = "Rendered cloud-init document from the node-config module."
  type        = string
  sensitive   = true
}

variable "ssh_port" { type = number }
variable "wireguard_port" { type = number }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "allow_icmp" { type = bool }

variable "tags" {
  type    = map(string)
  default = {}
}

# --- Linode specific --------------------------------------------------------

variable "region" {
  description = "Linode region. Must be one that offers the Metadata service, which cloud-init depends on."
  type        = string
  default     = "eu-west"
}

variable "instance_type" {
  description = "Linode plan. g6-nanode-1 is the cheapest shared instance and is ample for WireGuard."
  type        = string
  default     = "g6-nanode-1"
}

variable "image" {
  description = "Linode image slug."
  type        = string
  default     = "linode/ubuntu24.04"
}
