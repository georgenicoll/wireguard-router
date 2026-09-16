output "instance_id" {
  value = aws_instance.this.id
}

output "public_ipv4" {
  value = aws_instance.this.public_ip
}

output "public_ipv6" {
  value = try(one(aws_instance.this.ipv6_addresses), null)
}

output "platform" {
  value = "aws"
}
