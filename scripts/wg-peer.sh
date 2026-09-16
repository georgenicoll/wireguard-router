#!/usr/bin/env bash
#
# Manage the WireGuard key store and generate the tfvars that OpenTofu reads.
#
# Keys are created with the standard wireguard-tools (wg genkey / genpsk /
# pubkey) and kept in a private store outside this repository. The tfvars file
# is *derived* from that store: this script writes it, you never edit it.
#
#   ./scripts/wg-peer.sh add laptop 10.66.66.2   # new peer + client config
#   ./scripts/wg-peer.sh client laptop           # reprint a client config
#   ./scripts/wg-peer.sh list                    # show configured peers
#   ./scripts/wg-peer.sh remove laptop           # revoke a peer
#   ./scripts/wg-peer.sh regen                   # rebuild the tfvars
#   ./scripts/wg-peer.sh server-pubkey           # the server's public key
#   ./scripts/wg-peer.sh rotate-server --force   # new server key (breaks all clients)
#
# Store location, in order of preference:
#   $WGR_KEYS                       if set
#   $(dirname $WGR_CONFIG)/wireguard-router-keys
#
# Layout:
#   server.key                      the server private key, created once
#   peers/<name>/private.key        retained so client configs stay reprintable
#   peers/<name>/public.key
#   peers/<name>/preshared.key
#   peers/<name>/allowed_ips        tunnel addresses this peer may use
#   wireguard.generated.tfvars      generated; consumed automatically by ./wgr
#
set -euo pipefail

# Every secret this script creates is owner-read-only.
umask 077

PROG="$(basename "$0")"

die() { echo "error: $*" >&2; exit 1; }
note() { echo "$*" >&2; }

command -v wg >/dev/null 2>&1 ||
    die "'wg' not found. Install it with: sudo apt install wireguard-tools"

# --- Locate the key store ---------------------------------------------------

resolve_store() {
    if [[ -n "${WGR_KEYS:-}" ]]; then
        printf '%s' "$WGR_KEYS"
        return
    fi
    if [[ -n "${WGR_CONFIG:-}" ]]; then
        printf '%s' "$(cd "$(dirname "$WGR_CONFIG")" && pwd)/wireguard-router-keys"
        return
    fi
    die "set WGR_KEYS (or WGR_CONFIG, whose directory is used) to locate the key store"
}

STORE="$(resolve_store)"
PEERS_DIR="$STORE/peers"
SERVER_KEY="$STORE/server.key"
TFVARS="$STORE/wireguard.generated.tfvars"

# --- Helpers ----------------------------------------------------------------

valid_peer_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }

# A bare IPv4 address or one with a prefix length. Octet and prefix ranges are
# checked numerically: a regex alone would happily accept 999.1.1.1.
valid_ipv4() {
    local addr="${1%%/*}" octet
    [[ "$addr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    local IFS=.
    for octet in $addr; do
        ((10#$octet >= 0 && 10#$octet <= 255)) || return 1
    done
    if [[ "$1" == */* ]]; then
        local prefix="${1#*/}"
        [[ "$prefix" =~ ^[0-9]{1,2}$ ]] && ((10#$prefix <= 32)) || return 1
    fi
    return 0
}

valid_ipv6() {
    local addr="${1%%/*}"
    [[ "$addr" == *:* && "$addr" =~ ^[0-9a-fA-F:]+$ ]] || return 1
    if [[ "$1" == */* ]]; then
        local prefix="${1#*/}"
        [[ "$prefix" =~ ^[0-9]{1,3}$ ]] && ((10#$prefix <= 128)) || return 1
    fi
    return 0
}

valid_allowed_ip() { valid_ipv4 "$1" || valid_ipv6 "$1"; }

# Normalise "10.66.66.2" to "10.66.66.2/32" so the server routes exactly one
# address per peer; anything already carrying a prefix is left alone.
normalise_allowed_ips() {
    local raw="$1" out=() ip
    raw="${raw//,/ }"
    for ip in $raw; do
        [[ -z "$ip" ]] && continue
        valid_allowed_ip "$ip" || die "not a valid address or CIDR: $ip"
        if [[ "$ip" != */* ]]; then
            [[ "$ip" == *:* ]] && ip="$ip/128" || ip="$ip/32"
        fi
        out+=("$ip")
    done
    [[ ${#out[@]} -gt 0 ]] || die "no addresses given"
    printf '%s\n' "${out[@]}"
}

ensure_store() {
    mkdir -p "$PEERS_DIR"
    chmod 700 "$STORE" "$PEERS_DIR"
}

# Creates the server key only if it is absent, so no ordinary operation can
# ever rotate it out from under existing clients.
ensure_server_key() {
    ensure_store
    if [[ ! -f "$SERVER_KEY" ]]; then
        wg genkey > "$SERVER_KEY"
        chmod 600 "$SERVER_KEY"
        note "created a new server key at $SERVER_KEY"
    fi
}

server_pubkey() {
    [[ -f "$SERVER_KEY" ]] || die "no server key yet; run '$PROG add <name> <ip>' first"
    wg pubkey < "$SERVER_KEY"
}

peer_names() {
    [[ -d "$PEERS_DIR" ]] || return 0
    find "$PEERS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

# Pull the endpoint out of your main config file so client configs come out
# complete. Falls back to a placeholder when it cannot be determined.
derive_endpoint() {
    if [[ -n "${WGR_ENDPOINT:-}" ]]; then
        printf '%s' "$WGR_ENDPOINT"
        return
    fi
    local host="" port=""
    if [[ -n "${WGR_CONFIG:-}" && -r "${WGR_CONFIG:-}" ]]; then
        host=$(sed -nE 's/^[[:space:]]*dynu_hostname[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$WGR_CONFIG" | tail -1)
        port=$(sed -nE 's/^[[:space:]]*wireguard_port[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$WGR_CONFIG" | tail -1)
    fi
    [[ -z "$port" ]] && port="47654" # matches the variable default
    if [[ -n "$host" ]]; then
        printf '%s:%s' "$host" "$port"
    else
        printf '<dynu_hostname>:%s' "$port"
    fi
}

# --- tfvars generation ------------------------------------------------------

regen_tfvars() {
    [[ -f "$SERVER_KEY" ]] || die "no server key yet; nothing to generate"
    local tmp name pub psk ips first
    tmp="$(mktemp "${TMPDIR:-/tmp}/wgr-tfvars.XXXXXX")"

    {
        echo "# ---------------------------------------------------------------------------"
        echo "# GENERATED FILE - DO NOT EDIT."
        echo "#"
        echo "# Written by scripts/wg-peer.sh from the key store at:"
        echo "#   $STORE"
        echo "#"
        echo "# ./wgr passes this file to OpenTofu after your main config, so the values"
        echo "# here take precedence. Edit the key store and re-run the script instead."
        echo "# ---------------------------------------------------------------------------"
        echo
        printf 'wireguard_private_key = "%s"\n' "$(cat "$SERVER_KEY")"
        echo
        echo "wireguard_peers = ["
        while IFS= read -r name; do
            [[ -z "$name" ]] && continue
            pub="$PEERS_DIR/$name/public.key"
            [[ -f "$pub" ]] || { note "skipping '$name': no public.key"; continue; }
            echo "  {"
            printf '    %-13s = "%s"\n' "name" "$name"
            printf '    %-13s = "%s"\n' "public_key" "$(cat "$pub")"
            psk="$PEERS_DIR/$name/preshared.key"
            if [[ -s "$psk" ]]; then
                printf '    %-13s = "%s"\n' "preshared_key" "$(cat "$psk")"
            fi
            ips="$PEERS_DIR/$name/allowed_ips"
            printf '    %-13s = [' "allowed_ips"
            first=1
            while IFS= read -r ip; do
                [[ -z "$ip" ]] && continue
                [[ $first -eq 1 ]] || printf ', '
                printf '"%s"' "$ip"
                first=0
            done < "$ips"
            printf ']\n'
            echo "  },"
        done < <(peer_names)
        echo "]"
    } > "$tmp"

    chmod 600 "$tmp"
    mv "$tmp" "$TFVARS"
    note "wrote $TFVARS ($(peer_names | grep -c . || true) peer(s))"
}

# --- Client config ----------------------------------------------------------
print_client_config() {
    local name="$1" dir="$PEERS_DIR/$1" endpoint
    [[ -d "$dir" ]] || die "no such peer: $name (see '$PROG list')"
    endpoint="$(derive_endpoint)"

    echo "# WireGuard client config for '$name'"
    echo "# Save as /etc/wireguard/wg0.conf on Linux, or import into the mobile app."
    echo
    echo "[Interface]"
    echo "PrivateKey = $(cat "$dir/private.key")"
    printf 'Address = '
    paste -sd, "$dir/allowed_ips"
    echo "DNS = ${WGR_CLIENT_DNS:-1.1.1.1}"
    echo
    echo "[Peer]"
    echo "PublicKey = $(server_pubkey)"
    [[ -s "$dir/preshared.key" ]] && echo "PresharedKey = $(cat "$dir/preshared.key")"
    echo "Endpoint = $endpoint"
    echo "AllowedIPs = ${WGR_CLIENT_ROUTES:-0.0.0.0/0, ::/0}"
    echo "PersistentKeepalive = 25"

    if [[ "$endpoint" == "<"* ]]; then
        echo
        note "note: could not determine the endpoint; set dynu_hostname in your"
        note "      config file, or pass WGR_ENDPOINT=host:port, then re-run."
    fi
}

# --- Subcommands ------------------------------------------------------------

cmd_add() {
    local name="${1:-}" ips_raw="${2:-}"
    [[ -n "$name" && -n "$ips_raw" ]] || die "usage: $PROG add <name> <tunnel-ip>"
    valid_peer_name "$name" ||
        die "peer name must be lowercase alphanumeric with - or _, max 32 chars"

    local dir="$PEERS_DIR/$name"
    [[ -e "$dir" ]] && die "peer '$name' already exists (remove it first, or pick another name)"

    local ips
    ips="$(normalise_allowed_ips "$ips_raw")"

    # Two peers sharing a tunnel address would route unpredictably.
    local existing other
    while IFS= read -r other; do
        [[ -z "$other" ]] && continue
        while IFS= read -r existing; do
            [[ -z "$existing" ]] && continue
            while IFS= read -r wanted; do
                [[ "$existing" == "$wanted" ]] &&
                    die "address $wanted is already assigned to peer '$other'"
            done <<< "$ips"
        done < "$PEERS_DIR/$other/allowed_ips"
    done < <(peer_names)

    ensure_server_key
    mkdir -p "$dir"
    chmod 700 "$dir"

    wg genkey > "$dir/private.key"
    wg pubkey < "$dir/private.key" > "$dir/public.key"
    wg genpsk > "$dir/preshared.key"
    printf '%s\n' "$ips" > "$dir/allowed_ips"
    chmod 600 "$dir"/*

    note "added peer '$name' ($(paste -sd, "$dir/allowed_ips"))"
    regen_tfvars
    note ""
    note "Apply the change with: ./wgr <platform> apply"
    note ""
    print_client_config "$name"
}

cmd_client() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "usage: $PROG client <name>"
    print_client_config "$name"
}

cmd_list() {
    local n=0 name
    if [[ ! -f "$SERVER_KEY" ]]; then
        echo "No key store yet at $STORE"
        echo "Create one with: $PROG add <name> <tunnel-ip>"
        return
    fi
    echo "Key store:     $STORE"
    echo "Server pubkey: $(server_pubkey)"
    echo "Endpoint:      $(derive_endpoint)"
    echo "Generated:     $TFVARS$([[ -f "$TFVARS" ]] || echo '  (missing - run '"$PROG"' regen)')"
    echo
    printf '%-24s %s\n' "PEER" "ALLOWED IPS"
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        printf '%-24s %s\n' "$name" "$(paste -sd, "$PEERS_DIR/$name/allowed_ips" 2>/dev/null)"
        n=$((n + 1))
    done < <(peer_names)
    [[ $n -eq 0 ]] && echo "(none)"
    true
}

cmd_remove() {
    local name="${1:-}" force="${2:-}"
    [[ -n "$name" ]] || die "usage: $PROG remove <name> [--force]"
    local dir="$PEERS_DIR/$name"
    [[ -d "$dir" ]] || die "no such peer: $name"

    if [[ "$force" != "--force" ]]; then
        note "This permanently deletes the keys for '$name' and revokes its access."
        read -r -p "Remove peer '$name'? [y/N] " reply
        [[ "$reply" == "y" || "$reply" == "Y" ]] || { note "aborted"; exit 1; }
    fi

    rm -rf "$dir"
    note "removed peer '$name'"
    regen_tfvars
    note ""
    note "Revoke it on the server with: ./wgr <platform> apply"
}

cmd_rotate_server() {
    [[ "${1:-}" == "--force" ]] ||
        die "rotating the server key invalidates EVERY client config. Re-run with --force if you are sure."
    ensure_store
    wg genkey > "$SERVER_KEY"
    chmod 600 "$SERVER_KEY"
    note "new server key generated; public key is now $(server_pubkey)"
    regen_tfvars
    note ""
    note "Every client must be updated with the new PublicKey. Reprint them with:"
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        note "  $PROG client $name"
    done < <(peer_names)
}

usage() {
    sed -nE '2,/^set -euo/ s/^# ?//p' "$0" | sed '$d'
    exit 2
}

case "${1:-}" in
add)            shift; cmd_add "$@" ;;
client)         shift; cmd_client "$@" ;;
list|ls)        shift; cmd_list "$@" ;;
remove|rm)      shift; cmd_remove "$@" ;;
regen)          shift; regen_tfvars ;;
server-pubkey)  shift; server_pubkey ;;
rotate-server)  shift; cmd_rotate_server "$@" ;;
-h|--help|help|"") usage ;;
*)              die "unknown subcommand '$1' (try --help)" ;;
esac
