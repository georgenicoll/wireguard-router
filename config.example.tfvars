# ---------------------------------------------------------------------------
# Copy this file to a location OUTSIDE the repository, fill it in, and point
# WGR_CONFIG at it. It holds private keys and passwords, so it must never be
# committed.
#
#   cp config.example.tfvars ~/somewhere-private/wireguard-router.tfvars
#   export WGR_CONFIG=~/somewhere-private/wireguard-router.tfvars
#
# Every value here is cloud-agnostic: the same file drives the linode, aws,
# gcp and azure stacks unchanged.
# ---------------------------------------------------------------------------

node_name = "wg-router"
timezone  = "Europe/London"

# --- SSH access -------------------------------------------------------------

admin_username = "wgadmin"

# The public half of the key you will SSH with. Password login is disabled.
ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... you@yourmachine"

# Non-default port; sshd will not be reachable on 22.
ssh_port = 58022

# Narrow this to your own network if you have a static address.
allowed_ssh_cidrs = ["0.0.0.0/0"]

# --- WireGuard --------------------------------------------------------------

# Non-default UDP port. Clients must use this in their Endpoint.
wireguard_port = 47654

wireguard_address = "10.66.66.1/24"

# Generate with: wg genkey
# Keep this value stable across rebuilds so existing client configs keep working.
wireguard_private_key = "REPLACE_ME_WITH_OUTPUT_OF_wg_genkey"

# Route peers' general internet traffic out through the server.
wireguard_nat = true

wireguard_peers = [
  {
    name        = "laptop"
    public_key  = "REPLACE_WITH_CLIENT_PUBLIC_KEY"
    allowed_ips = ["10.66.66.2/32"]
    # Optional extra symmetric layer; generate with: wg genpsk
    # preshared_key = "..."
  },
  {
    name                 = "phone"
    public_key           = "REPLACE_WITH_CLIENT_PUBLIC_KEY"
    allowed_ips          = ["10.66.66.3/32"]
    persistent_keepalive = 25
  },
]

# --- Dynu dynamic DNS -------------------------------------------------------

dynu_hostname        = "yourname.freeddns.org"
dynu_username        = "your-dynu-username"
dynu_password        = "your-dynu-password"
dynu_update_interval = "5min"

# --- Provider selection -----------------------------------------------------
# Only the block matching the stack you run is used; unknown variables in a
# var file are an error, so keep just the ones you need or leave all of them
# (each stack declares its own, so remove blocks for stacks you never run).

# Linode
region        = "eu-west"
instance_type = "g6-nanode-1"
linode_token  = "" # prefer: export LINODE_TOKEN=...
