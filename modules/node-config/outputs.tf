output "cloud_init" {
  description = "Rendered cloud-config document. Feed this to the platform module's user-data input."
  value       = local.cloud_init
  sensitive   = true

  # Caught here rather than at runtime, so a missing credential fails the plan
  # instead of producing a server that silently never updates its DNS.
  precondition {
    condition = var.dynu_api_key != "" || (var.dynu_username != "" && var.dynu_password != "")
    error_message = join(" ", [
      "No Dynu credentials configured.",
      "Set dynu_api_key (preferred), or both dynu_username and dynu_password.",
    ])
  }

  # Both methods at once is almost certainly a mistake, and only the API key
  # would actually be used.
  precondition {
    condition     = var.dynu_api_key == "" || (var.dynu_username == "" && var.dynu_password == "")
    error_message = "Set either dynu_api_key or dynu_username/dynu_password, not both: the API key would take precedence."
  }
}

output "cloud_init_base64" {
  description = "Base64 of the cloud-config, for providers that require encoded user-data."
  value       = base64encode(local.cloud_init)
  sensitive   = true
}

output "wireguard_config" {
  description = "The rendered server-side wg0.conf, for inspection."
  value       = local.wireguard_config
  sensitive   = true
}
