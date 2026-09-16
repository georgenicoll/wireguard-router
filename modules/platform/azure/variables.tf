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

# Azure's VM resource requires the admin user and key up front, rather than
# leaving both entirely to cloud-init as the other platforms do.
variable "admin_username" { type = string }
variable "ssh_public_key" { type = string }

# --- Azure specific ---------------------------------------------------------

variable "location" {
  type    = string
  default = "uksouth"
}

variable "vm_size" {
  description = "Standard_B1ls is the cheapest Linux size (1 vCPU burstable, 0.5 GiB)."
  type        = string
  default     = "Standard_B1ls"
}

variable "image" {
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

variable "address_space" {
  type    = string
  default = "10.90.0.0/24"
}
