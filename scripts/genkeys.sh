#!/usr/bin/env bash
# Generate a WireGuard server keypair plus one client keypair, and print the
# snippets to paste into your config file and into the client.
#
# Usage: scripts/genkeys.sh [client-name] [client-tunnel-ip]
set -euo pipefail

if ! command -v wg >/dev/null 2>&1; then
    echo "error: 'wg' not found. Install it with: sudo apt install wireguard-tools" >&2
    exit 1
fi

CLIENT_NAME="${1:-laptop}"
CLIENT_IP="${2:-10.66.66.2}"

umask 077
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(printf '%s' "$SERVER_PRIV" | wg pubkey)
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(printf '%s' "$CLIENT_PRIV" | wg pubkey)
PSK=$(wg genpsk)

cat <<OUT

# ======================================================================
# For your config file (the one WGR_CONFIG points at)
# ======================================================================

wireguard_private_key = "$SERVER_PRIV"

wireguard_peers = [
  {
    name          = "$CLIENT_NAME"
    public_key    = "$CLIENT_PUB"
    preshared_key = "$PSK"
    allowed_ips   = ["$CLIENT_IP/32"]
  },
]

# ======================================================================
# For the client. Endpoint comes from: ./wgr <platform> output wireguard_endpoint
# ======================================================================

[Interface]
PrivateKey = $CLIENT_PRIV
Address = $CLIENT_IP/32
DNS = 1.1.1.1

[Peer]
PublicKey = $SERVER_PUB
PresharedKey = $PSK
Endpoint = <dynu_hostname>:<wireguard_port>
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25

# Server public key: $SERVER_PUB
# These secrets are printed once and not written to disk. Store them safely.
OUT
