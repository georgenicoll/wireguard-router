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
variable "ssh_public_keys" { type = list(string) }

# --- Azure specific ---------------------------------------------------------

variable "location" {
  type    = string
  default = "uksouth"
}

variable "vm_size" {
  description = "Standard_B2ts_v2 is a cheap burstable Linux size (2 vCPU, 1 GiB). The older v1 Bs family (B1ls etc.) is NotAvailableForSubscription on some subscriptions/regions - see AZURE_SETUP.md."
  type        = string
  default     = "Standard_B2ts_v2"
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
