# Azure-only inputs. Credentials come from `az login` or an ARM_* service principal.

variable "azure_subscription_id" {
  description = "Azure subscription ID. Also readable from ARM_SUBSCRIPTION_ID."
  type        = string
  default     = null
}

variable "azure_location" {
  type    = string
  default = "uksouth"
}

variable "vm_size" {
  description = "Standard_B1ls is the cheapest Linux size."
  type        = string
  default     = "Standard_B1ls"
}
