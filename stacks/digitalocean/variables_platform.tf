# DigitalOcean-only inputs. Everything else lives in variables_common.tf.

variable "do_token" {
  description = "DigitalOcean API token. Prefer the DIGITALOCEAN_TOKEN environment variable and leave this empty."
  type        = string
  sensitive   = true
  default     = ""
}

variable "region" {
  description = "DigitalOcean region slug (e.g. lon1 for London)."
  type        = string
  default     = "lon1"
}

variable "droplet_size" {
  description = "Droplet size slug. s-1vcpu-512mb-10gb is the cheapest option."
  type        = string
  default     = "s-1vcpu-512mb-10gb"
}

variable "image" {
  description = "DigitalOcean image slug."
  type        = string
  default     = "ubuntu-24-04-x64"
}
