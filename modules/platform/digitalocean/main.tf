resource "digitalocean_droplet" "this" {
  name   = var.node_name
  region = var.region
  size   = var.droplet_size
  image  = var.image
  ipv6   = true

  # DigitalOcean's decoded user_data limit is 64KB, well clear of what a
  # cloud-init document with a handful of site-to-site peers needs, so unlike
  # Linode/AWS this is passed straight through, uncompressed.
  user_data = var.user_data

  tags = [for k, v in var.tags : "${k}:${v}"]

  lifecycle {
    # The instance is disposable, but never silently replace it because a new
    # image slug appeared upstream.
    ignore_changes = [image]
  }
}

# Cloud-level firewall. This is the outer of two layers; ufw on the host is the
# inner one, so a misconfiguration in either alone does not expose the server.
resource "digitalocean_firewall" "this" {
  name        = "${replace(var.node_name, "_", "-")}-fw"
  droplet_ids = [digitalocean_droplet.this.id]

  inbound_rule {
    protocol   = "tcp"
    port_range = tostring(var.ssh_port)
    source_addresses = concat(
      var.allowed_ssh_cidrs,
      contains(var.allowed_ssh_cidrs, "0.0.0.0/0") ? ["::/0"] : []
    )
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = tostring(var.wireguard_port)
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  dynamic "inbound_rule" {
    for_each = var.allow_icmp ? [1] : []
    content {
      protocol         = "icmp"
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # DigitalOcean firewalls default-deny in both directions, so outbound needs
  # its own explicit "allow everything" rules.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
