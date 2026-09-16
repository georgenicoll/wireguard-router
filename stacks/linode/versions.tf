terraform {
  required_version = ">= 1.6.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.13"
    }
  }
}

provider "linode" {
  # Falls back to the LINODE_TOKEN environment variable when unset.
  token = var.linode_token != "" ? var.linode_token : null
}
