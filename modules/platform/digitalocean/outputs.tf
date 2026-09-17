output "instance_id" {
  value = digitalocean_droplet.this.id
}

output "public_ipv4" {
  value = digitalocean_droplet.this.ipv4_address
}

output "public_ipv6" {
  value = try(digitalocean_droplet.this.ipv6_address, null)
}

output "platform" {
  value = "digitalocean"
}
