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

# --- AWS specific -----------------------------------------------------------

variable "instance_type" {
  description = "t4g.nano is the cheapest current-generation instance; it is arm64, matching the AMI filter below."
  type        = string
  default     = "t4g.nano"
}

variable "architecture" {
  description = "CPU architecture of the Ubuntu AMI to select. Must match instance_type."
  type        = string
  default     = "arm64"
}

variable "ubuntu_release" {
  type    = string
  default = "24.04"
}

variable "vpc_id" {
  description = "VPC to launch into. Empty uses the account's default VPC."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet to launch into. Empty picks a default-VPC subnet that assigns public IPs."
  type        = string
  default     = ""
}

variable "root_volume_size" {
  type    = number
  default = 8
}
