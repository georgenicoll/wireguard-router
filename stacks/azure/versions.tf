terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  subscription_id = var.azure_subscription_id
  features {}

  # By default the provider tries to register every resource provider it
  # supports (far more than this stack uses), which a scoped-down service
  # principal isn't granted rights for. Skip it - Compute/Network/Resources
  # are already registered on essentially any subscription that's been used
  # before.
  resource_provider_registrations = "none"
}
