output "cloud_init" {
  description = "Rendered cloud-config document. Feed this to the platform module's user-data input."
  value       = local.cloud_init
  sensitive   = true
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
