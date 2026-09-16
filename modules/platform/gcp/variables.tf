variable "node_name" { type = string }

variable "user_data" {
  type      = string
  sensitive = true
}

variable "ssh_port" { type = number }
variable "wireguard_port" { type = number }
variable "allowed_ssh_cidrs" { type = list(string) }
variable "allow_icmp" { type = bool }

variable "tags" {
  type    = map(string)
  default = {}
}

# --- GCP specific -----------------------------------------------------------

variable "zone" {
  description = "Zone to launch in. e2-micro is free-tier eligible only in us-west1, us-central1 and us-east1."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  description = "e2-micro is the cheapest shared-core machine and is free-tier eligible in some regions."
  type        = string
  default     = "e2-micro"
}

variable "image" {
  type    = string
  default = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "network" {
  type    = string
  default = "default"
}

variable "disk_size" {
  type    = number
  default = 10
}
