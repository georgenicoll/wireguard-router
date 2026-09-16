# All inputs are passed straight through from the stack's shared variables.
# This module contains no provider-specific logic whatsoever: its only job is
# to turn configuration into a cloud-init document any cloud can consume.

variable "node_name" { type = string }
variable "timezone" { type = string }

variable "admin_username" { type = string }
variable "ssh_public_key" { type = string }
variable "ssh_port" { type = number }
variable "allowed_ssh_cidrs" { type = list(string) }

variable "wireguard_interface" { type = string }
variable "wireguard_port" { type = number }
variable "wireguard_address" { type = string }
variable "wireguard_address_v6" { type = string }
variable "wireguard_mtu" { type = number }
variable "wireguard_nat" { type = bool }

variable "wireguard_private_key" {
  type      = string
  sensitive = true
}

variable "wireguard_peers" {
  type = list(object({
    name                 = string
    public_key           = string
    allowed_ips          = list(string)
    preshared_key        = optional(string)
    persistent_keepalive = optional(number)
  }))
  sensitive = true
}

variable "dynu_hostname" { type = string }

variable "dynu_username" {
  type      = string
  sensitive = true
}

variable "dynu_password" {
  type      = string
  sensitive = true
}

variable "dynu_update_interval" { type = string }

variable "extra_packages" { type = list(string) }
