# GCP-only inputs. Credentials come from `gcloud auth application-default login`
# or GOOGLE_APPLICATION_CREDENTIALS.

variable "gcp_project" {
  description = "GCP project ID to create the instance in."
  type        = string
}

variable "gcp_zone" {
  description = "Zone. e2-micro is free-tier eligible only in us-west1, us-central1 and us-east1."
  type        = string
  default     = "us-central1-a"
}

variable "machine_type" {
  type    = string
  default = "e2-micro"
}

variable "image" {
  type    = string
  default = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
}

variable "network" {
  type    = string
  default = "default"
}
