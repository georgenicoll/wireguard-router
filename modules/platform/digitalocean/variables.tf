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

# --- DigitalOcean specific ---------------------------------------------------

variable "region" {
  description = "DigitalOcean region slug."
  type        = string
  default     = "lon1"
}

variable "droplet_size" {
  description = "Droplet size slug. s-1vcpu-512mb-10gb is the cheapest, and ample for WireGuard."
  type        = string
  default     = "s-1vcpu-512mb-10gb"
}

variable "image" {
  description = "DigitalOcean image slug."
  type        = string
  default     = "ubuntu-24-04-x64"
}
