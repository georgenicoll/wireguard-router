locals {
  # `ip_address` is deprecated, so derive the public address from the full set.
  # Linode's regional private range is 192.168.128.0/17; filter it out so the
  # output is the routable address even if private networking is turned on.
  public_ipv4_addresses = sort([
    for ip in linode_instance.this.ipv4 : ip if !startswith(ip, "192.168.")
  ])
}

output "instance_id" {
  value = tostring(linode_instance.this.id)
}

output "public_ipv4" {
  value = local.public_ipv4_addresses[0]
}

output "public_ipv6" {
  # Linode reports IPv6 as a /128 CIDR; strip it to a bare address.
  value = try(split("/", linode_instance.this.ipv6)[0], null)
}

output "platform" {
  value = "linode"
}
