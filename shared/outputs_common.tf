# ---------------------------------------------------------------------------
# Outputs common to every stack. Symlinked into stacks/*; relies only on the
# standard platform-module interface, so it works unchanged on all providers.
# ---------------------------------------------------------------------------

output "platform" {
  description = "Which cloud this server is currently running on."
  value       = module.server.platform
}

output "instance_id" {
  description = "Provider-assigned instance identifier."
  value       = module.server.instance_id
}

output "public_ipv4" {
  description = "Public IPv4 address of the server."
  value       = module.server.public_ipv4
}

output "public_ipv6" {
  description = "Public IPv6 address, where the provider assigns one."
  value       = module.server.public_ipv6
}

output "ssh_command" {
  description = "Ready-to-paste SSH command."
  value       = "ssh -p ${var.ssh_port} ${var.admin_username}@${module.server.public_ipv4}"
}

output "wireguard_endpoint" {
  description = "Endpoint value for client configs. Uses the dynamic hostname so it survives a rebuild on any provider."
  value       = "${var.dynu_hostname}:${var.wireguard_port}"
}

output "post_apply_notes" {
  description = "What to check once the server is up."
  value = trimspace(<<-EOT
    Provisioning is asynchronous: cloud-init continues for a few minutes after apply returns.

      ssh -p ${var.ssh_port} ${var.admin_username}@${module.server.public_ipv4}
      sudo cloud-init status --wait
      sudo wg show
      systemctl status dynu-update.timer
      journalctl -u dynu-update.service -n 20

    Clients should use Endpoint = ${var.dynu_hostname}:${var.wireguard_port}
  EOT
  )
}
