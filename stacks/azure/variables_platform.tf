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
  description = "Standard_B2ts_v2 is a cheap burstable Linux size. The older v1 Bs family (B1ls etc.) is NotAvailableForSubscription on some subscriptions/regions - see AZURE_SETUP.md."
  type        = string
  default     = "Standard_B2ts_v2"
}
