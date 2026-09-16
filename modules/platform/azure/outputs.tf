output "instance_id" {
  value = azurerm_linux_virtual_machine.this.id
}

output "public_ipv4" {
  value = azurerm_public_ip.this.ip_address
}

output "public_ipv6" {
  value = null
}

output "platform" {
  value = "azure"
}
