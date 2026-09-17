terraform {
  required_version = ">= 1.6.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.34"
    }
  }
}

provider "digitalocean" {
  # Falls back to the DIGITALOCEAN_TOKEN environment variable when unset.
  token = var.do_token != "" ? var.do_token : null
}
