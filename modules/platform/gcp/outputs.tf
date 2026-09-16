output "instance_id" {
  value = google_compute_instance.this.instance_id
}

output "public_ipv4" {
  value = google_compute_address.this.address
}

output "public_ipv6" {
  value = null
}

output "platform" {
  value = "gcp"
}
