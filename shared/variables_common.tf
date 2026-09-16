# ---------------------------------------------------------------------------
# Cloud-agnostic inputs.
#
# This file is symlinked into every stack under stacks/*, so all providers
# accept exactly the same variables and can be driven from one shared
# values file. Edit it here and every stack picks the change up.
# ---------------------------------------------------------------------------

variable "node_name" {
  description = "Hostname / resource name prefix for the server."
  type        = string
  default     = "wg-router"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{0,30}[a-z0-9]$", var.node_name))
    error_message = "node_name must be lowercase alphanumeric with hyphens, 2-32 chars."
  }
}

variable "timezone" {
  description = "IANA timezone for the server clock."
  type        = string
  default     = "Etc/UTC"
}

# --- SSH access -------------------------------------------------------------

variable "admin_username" {
  description = "Unprivileged sudo user created for SSH access. Root login is disabled."
  type        = string
  default     = "wgadmin"
}

variable "ssh_public_key" {
  description = "OpenSSH public key authorised for the admin user (the full 'ssh-ed25519 AAAA... comment' line)."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp256|sk-ssh-ed25519@openssh.com) ", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be a valid OpenSSH public key line, not a file path or private key."
  }
}

variable "ssh_port" {
  description = "Non-default TCP port for sshd. Moving off 22 removes the bulk of background scanning."
  type        = number
  default     = 58022

  validation {
    condition     = var.ssh_port > 1024 && var.ssh_port <= 65535
    error_message = "ssh_port must be between 1025 and 65535."
  }
}

variable "allowed_ssh_cidrs" {
  description = "Source CIDRs permitted to reach the SSH port. Narrow this to your own network if you have a static IP."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allow_icmp" {
  description = "Permit inbound ICMP echo (ping). Useful for diagnosing connectivity."
  type        = bool
  default     = true
}

# --- WireGuard --------------------------------------------------------------

variable "wireguard_port" {
  description = "Non-default UDP port for WireGuard. Must match the Endpoint in every client config."
  type        = number
  default     = 47654

  validation {
    condition     = var.wireguard_port > 1024 && var.wireguard_port <= 65535
    error_message = "wireguard_port must be between 1025 and 65535."
  }
}

variable "wireguard_interface" {
  description = "Name of the WireGuard interface."
  type        = string
  default     = "wg0"
}

variable "wireguard_address" {
  description = "Server address on the WireGuard tunnel, in CIDR form (e.g. 10.66.66.1/24)."
  type        = string
  default     = "10.66.66.1/24"
}

variable "wireguard_address_v6" {
  description = "Optional IPv6 address for the tunnel (e.g. fd66:66:66::1/64). Empty disables tunnel IPv6."
  type        = string
  default     = ""
}

variable "wireguard_private_key" {
  description = "Base64 WireGuard private key for the server. Keep this stable across rebuilds so client configs keep working."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$", trimspace(var.wireguard_private_key)))
    error_message = "wireguard_private_key must be a 44-character base64 WireGuard key (generate with: wg genkey)."
  }
}

variable "wireguard_mtu" {
  description = "Optional MTU override for the tunnel. 0 lets wg-quick choose."
  type        = number
  default     = 0
}

variable "wireguard_peers" {
  description = <<-EOT
    Clients permitted onto the tunnel. allowed_ips are the addresses each peer
    may use *inside* the tunnel, and must not overlap between peers.
  EOT
  type = list(object({
    name                 = string
    public_key           = string
    allowed_ips          = list(string)
    preshared_key        = optional(string)
    persistent_keepalive = optional(number)
  }))
  default   = []
  sensitive = true

  validation {
    condition     = length(distinct([for p in var.wireguard_peers : p.public_key])) == length(var.wireguard_peers)
    error_message = "Each WireGuard peer must have a unique public_key."
  }

  validation {
    condition     = alltrue([for p in var.wireguard_peers : length(p.allowed_ips) > 0])
    error_message = "Every WireGuard peer needs at least one entry in allowed_ips."
  }
}

variable "wireguard_nat" {
  description = "Masquerade tunnel traffic out of the server's default interface, so peers can reach the internet through it."
  type        = bool
  default     = true
}

variable "wireguard_dns" {
  description = <<-EOT
    Default DNS server handed to peers in their client config, e.g. a
    resolver reachable through one peer's routed LAN. Empty means no
    network-wide default; scripts/wg-peer.sh falls back to a public resolver
    unless a peer has its own override (see wg-peer.sh add --dns).
  EOT
  type        = string
  default     = ""
}

variable "wireguard_client_routes" {
  description = <<-EOT
    Default client-side AllowedIPs handed to peers in their client config.
    "auto" computes the tunnel network plus every other peer's own address
    and LAN subnet (see scripts/wg-peer.sh), so a mesh of site-to-site peers
    can reach each other without also routing general internet traffic
    through the server. A literal CIDR list is used as-is. Empty means full
    tunnel: "0.0.0.0/0, ::/0". Overridden per invocation by WGR_CLIENT_ROUTES.
  EOT
  type        = string
  default     = ""
}

# --- Dynu dynamic DNS -------------------------------------------------------

variable "dynu_hostname" {
  description = "The fully-qualified dynamic hostname to keep pointed at this server (e.g. myrouter.freeddns.org)."
  type        = string
}

variable "dynu_api_key" {
  description = <<-EOT
    Dynu API key, from the API Credentials page of the control panel. Preferred
    over username/password: it is revocable on its own, and it does not grant
    control-panel access if the server is ever compromised. Uses Dynu's v2 REST
    API rather than the legacy IP-update protocol.
  EOT
  type        = string
  sensitive   = true
  default     = ""
}

variable "dynu_username" {
  description = "Dynu account username. Only used by the legacy IP-update protocol; leave empty when dynu_api_key is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "dynu_password" {
  description = "Dynu account password. Only used by the legacy IP-update protocol; leave empty when dynu_api_key is set."
  type        = string
  sensitive   = true
  default     = ""
}

variable "dynu_update_interval" {
  description = "How often to re-check the public IP, as a systemd time span."
  type        = string
  default     = "5min"
}

# --- Misc -------------------------------------------------------------------

variable "extra_packages" {
  description = "Additional apt packages to install on the node."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Free-form tags applied to cloud resources where the provider supports them."
  type        = map(string)
  default     = {}
}
