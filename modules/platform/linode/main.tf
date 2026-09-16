resource "linode_instance" "this" {
  label  = var.node_name
  region = var.region
  type   = var.instance_type
  image  = var.image

  # No private networking: this host only needs its public interface.
  private_ip = false

  tags = [for k, v in var.tags : "${k}:${v}"]

  metadata {
    # Linode caps decoded user_data at 16384 bytes, and a cloud-init document
    # with a couple of site-to-site peers clears that easily. Gzipping first
    # is the standard trick for this: cloud-init auto-detects the gzip magic
    # bytes and decompresses transparently, regardless of which cloud
    # delivered it, so nothing on the server side needs to know this happened.
    user_data = base64gzip(var.user_data)
  }

  lifecycle {
    # The instance is disposable, but never silently replace it because a new
    # image slug appeared upstream.
    ignore_changes = [image]
  }
}

# Cloud-level firewall. This is the outer of two layers; ufw on the host is the
# inner one, so a misconfiguration in either alone does not expose the server.
resource "linode_firewall" "this" {
  label = substr("${replace(var.node_name, "_", "-")}-fw", 0, 32)

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.ssh_port)
    ipv4     = var.allowed_ssh_cidrs
    ipv6     = contains(var.allowed_ssh_cidrs, "0.0.0.0/0") ? ["::/0"] : []
  }

  inbound {
    label    = "allow-wireguard"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = tostring(var.wireguard_port)
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  dynamic "inbound" {
    for_each = var.allow_icmp ? [1] : []
    content {
      label    = "allow-icmp"
      action   = "ACCEPT"
      protocol = "ICMP"
      ipv4     = ["0.0.0.0/0"]
      ipv6     = ["::/0"]
    }
  }

  linodes = [linode_instance.this.id]
  tags    = [for k, v in var.tags : "${k}:${v}"]
}
