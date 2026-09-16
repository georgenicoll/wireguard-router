terraform {
  required_version = ">= 1.6.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.30"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = replace(var.gcp_zone, "/-[a-z]$/", "")
  zone    = var.gcp_zone
}
