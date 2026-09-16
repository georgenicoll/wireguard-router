#!/usr/bin/env bash
#
# Manage the WireGuard key store and generate the tfvars that OpenTofu reads.
#
# Keys are created with the standard wireguard-tools (wg genkey / genpsk /
# pubkey) and kept in a private store outside this repository. The tfvars file
# is *derived* from that store: this script writes it, you never edit it.
#
#   ./scripts/wg-peer.sh add laptop 10.66.66.2        # simple client, no LAN behind it
#   ./scripts/wg-peer.sh add router 10.73.73.2 \
#       --lan 10.2.73.0/24 --dns 10.2.73.1            # site-to-site: routes a whole LAN
#   ./scripts/wg-peer.sh update router --dns 10.2.73.5  # change metadata, keep its keys
#   ./scripts/wg-peer.sh client laptop                # reprint a client config
#   ./scripts/wg-peer.sh list                         # show configured peers
#   ./scripts/wg-peer.sh remove laptop                # revoke a peer
#   ./scripts/wg-peer.sh regen                        # rebuild the tfvars
#   ./scripts/wg-peer.sh server-pubkey                # the server's public key
#   ./scripts/wg-peer.sh rotate-server --force        # new server key (breaks all clients)
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
#   peers/<name>/own_ip             the peer's single address on the tunnel (/32 or /128)
#   peers/<name>/lan_subnet         optional: a real LAN this peer routes to the tunnel
#   peers/<name>/dns                optional: DNS override for this peer's client config
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
command -v python3 >/dev/null 2>&1 ||
    die "'python3' not found. It is used for correct CIDR/subnet-overlap checks."

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

# --- Basic validators --------------------------------------------------------

valid_peer_name() { [[ "$1" =~ ^[a-z0-9][a-z0-9_-]{0,31}$ ]]; }

# Octet and prefix ranges are checked numerically: a regex alone would happily
# accept 999.1.1.1.
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

valid_cidr() { valid_ipv4 "$1" || valid_ipv6 "$1"; }

# A bare address, no prefix - for DNS server entries.
valid_ip_address() { [[ "$1" != */* ]] && valid_cidr "$1"; }

# --- CIDR arithmetic (delegated to python3's ipaddress module) --------------

# Prints the canonical network for a CIDR, masking off any host bits. Used so
# stored subnets are unambiguous on disk (10.2.73.5/24 -> 10.2.73.0/24).
canonical_network() {
    python3 -c "import ipaddress,sys; print(ipaddress.ip_network(sys.argv[1], strict=False))" "$1"
}

# True (exit 0) if two CIDRs share any address. This is real subnet overlap,
# not string comparison - 10.73.73.2/24 and 10.73.73.3/24 look different as
# text but are the same network, and this catches that.
cidr_overlaps() {
    python3 -c "
import ipaddress, sys
a = ipaddress.ip_network(sys.argv[1], strict=False)
b = ipaddress.ip_network(sys.argv[2], strict=False)
sys.exit(0 if a.overlaps(b) else 1)
" "$1" "$2"
}


# Normalise a peer's own tunnel address: must be exactly one host, so an
# explicit prefix shorter than full length is rejected rather than silently
# treated as "route this whole subnet to this peer" (the mistake that started
# this feature: 10.73.73.2/24 and 10.73.73.3/24 both mean the whole /24).
normalise_own_ip() {
    local ip="$1"
    valid_cidr "$ip" || die "not a valid address: $ip"
    if [[ "$ip" == */* ]]; then
        local prefix="${ip#*/}"
        if [[ "$ip" == *:* ]]; then
            [[ "$prefix" == "128" ]] ||
                die "a peer's own address must be a single host (/128), not a subnet: $ip"
        else
            [[ "$prefix" == "32" ]] ||
                die "a peer's own address must be a single host (/32), not a subnet: $ip"
        fi
        printf '%s' "$ip"
    else
        [[ "$ip" == *:* ]] && printf '%s/128' "$ip" || printf '%s/32' "$ip"
    fi
}

# Normalise a LAN subnet: requires an explicit prefix (a bare address here is
# almost certainly a mistake - use own_ip / --lan correctly instead), and
# canonicalises host bits so what is on disk always matches what wg will
# actually route.
normalise_lan_subnet() {
    local cidr="$1" canon
    [[ -n "$cidr" ]] || die "empty LAN subnet"
    [[ "$cidr" == */* ]] ||
        die "a LAN subnet needs an explicit prefix, e.g. 10.2.73.0/24: $cidr"
    valid_cidr "$cidr" || die "not a valid subnet: $cidr"
    canon="$(canonical_network "$cidr")"
    if [[ "$canon" != "$cidr" ]]; then
        note "note: $cidr has host bits set; storing it as the network $canon"
    fi
    printf '%s' "$canon"
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

peer_own_ip() { cat "$PEERS_DIR/$1/own_ip" 2>/dev/null || true; }
peer_lan_subnet() { cat "$PEERS_DIR/$1/lan_subnet" 2>/dev/null || true; }
peer_dns() { cat "$PEERS_DIR/$1/dns" 2>/dev/null || true; }

# The full AllowedIPs list for a peer: its own address, plus its routed LAN
# if it has one.
peer_allowed_ips() {
    local name="$1" own lan
    own="$(peer_own_ip "$name")"
    [[ -n "$own" ]] || die "peer '$name' has no own_ip (old-format peer?). Fix with: $PROG update $name --ip <address>"
    printf '%s\n' "$own"
    lan="$(peer_lan_subnet "$name")"
    [[ -n "$lan" ]] && printf '%s\n' "$lan"
}

# Pull a value out of your main config file by variable name. Used for the
# endpoint and the network-wide default DNS, so client configs come out
# complete without duplicating those settings here.
config_value() {
    local var="$1"
    [[ -n "${WGR_CONFIG:-}" && -r "${WGR_CONFIG:-}" ]] || return 0
    sed -nE "s/^[[:space:]]*${var}[[:space:]]*=[[:space:]]*\"([^\"]*)\".*/\1/p" "$WGR_CONFIG" | tail -1
}

derive_endpoint() {
    if [[ -n "${WGR_ENDPOINT:-}" ]]; then
        printf '%s' "$WGR_ENDPOINT"
        return
    fi
    local host port
    host="$(config_value dynu_hostname)"
    port="$(sed -nE 's/^[[:space:]]*wireguard_port[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "${WGR_CONFIG:-/dev/null}" 2>/dev/null | tail -1)"
    [[ -z "$port" ]] && port="47654" # matches the variable default
    if [[ -n "$host" ]]; then
        printf '%s:%s' "$host" "$port"
    else
        printf '<dynu_hostname>:%s' "$port"
    fi
}

# The tunnel's own network (wireguard_address in your config, defaulting to
# match the tofu variable), used to warn if a peer's own_ip looks unrelated to
# it, and to refuse a LAN subnet that collides with the tunnel itself.
derive_tunnel_network() {
    local addr
    addr="$(config_value wireguard_address)"
    [[ -z "$addr" ]] && addr="10.66.66.1/24" # matches the variable default
    canonical_network "$addr"
}

# The network-wide default DNS from your config, if set.
derive_default_dns() {
    config_value wireguard_dns
}

# The network-wide default client-side AllowedIPs from your config, if set
# ("auto" or a literal CIDR list).
derive_default_routes() {
    config_value wireguard_client_routes
}

# --- Overlap checking ---------------------------------------------------------

# Every address range a peer currently occupies (own_ip and, if present,
# lan_subnet), across every peer except the one named in $1 (used by `update`
# so a peer's own existing ranges do not conflict with themselves).
claimed_ranges() {
    local skip="${1:-}" name own lan
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "$skip" ]] && continue
        own="$(peer_own_ip "$name")"
        [[ -n "$own" ]] && printf '%s\t%s\n' "$own" "$name"
        lan="$(peer_lan_subnet "$name")"
        [[ -n "$lan" ]] && printf '%s\t%s\n' "$lan" "$name"
    done < <(peer_names)
}

# Dies if $1 (a CIDR) overlaps anything already claimed, other than by the
# peer named in $2 (its own prior values, for `update`). $3 is "own_ip" or
# "lan_subnet": an own_ip is *expected* to sit inside the tunnel network, so
# that check is skipped for it; a lan_subnet must never overlap the tunnel
# network at all, even if it is fully contained by (or equal to) it - that
# would still mean routing addresses already used by every other peer and the
# server itself to just one peer.
check_no_overlap() {
    local candidate="$1" skip="$2" kind="$3" range owner tunnel
    while IFS=$'\t' read -r range owner; do
        [[ -z "$range" ]] && continue
        cidr_overlaps "$candidate" "$range" &&
            die "$candidate overlaps $range, already used by peer '$owner'"
    done < <(claimed_ranges "$skip")

    if [[ "$kind" == "lan_subnet" ]]; then
        tunnel="$(derive_tunnel_network)"
        cidr_overlaps "$candidate" "$tunnel" &&
            die "$candidate overlaps the tunnel network $tunnel (wireguard_address); a LAN subnet cannot include tunnel addresses"
    fi
    return 0
}

# --- tfvars generation ------------------------------------------------------

regen_tfvars() {
    [[ -f "$SERVER_KEY" ]] || die "no server key yet; nothing to generate"
    local tmp name pub psk first ip
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
            if [[ ! -f "$pub" ]]; then
                note "skipping '$name': no public.key"
                continue
            fi
            if [[ ! -f "$PEERS_DIR/$name/own_ip" ]]; then
                note "skipping '$name': old-format peer with no own_ip."
                note "  Fix with: $PROG update $name --ip <address>"
                continue
            fi
            echo "  {"
            printf '    %-13s = "%s"\n' "name" "$name"
            printf '    %-13s = "%s"\n' "public_key" "$(cat "$pub")"
            psk="$PEERS_DIR/$name/preshared.key"
            if [[ -s "$psk" ]]; then
                printf '    %-13s = "%s"\n' "preshared_key" "$(cat "$psk")"
            fi
            printf '    %-13s = [' "allowed_ips"
            first=1
            while IFS= read -r ip; do
                [[ -z "$ip" ]] && continue
                [[ $first -eq 1 ]] || printf ', '
                printf '"%s"' "$ip"
                first=0
            done < <(peer_allowed_ips "$name")
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

# Precedence: an explicit WGR_CLIENT_DNS wins outright (an ad-hoc override for
# this one printout); then the peer's own stored --dns; then the network-wide
# wireguard_dns default from your config; then a public fallback.
effective_dns() {
    local name="$1" own
    if [[ -n "${WGR_CLIENT_DNS:-}" ]]; then
        printf '%s' "$WGR_CLIENT_DNS"
        return
    fi
    own="$(peer_dns "$name")"
    [[ -n "$own" ]] && { printf '%s' "$own"; return; }
    own="$(derive_default_dns)"
    [[ -n "$own" ]] && { printf '%s' "$own"; return; }
    printf '1.1.1.1'
}

# The tunnel network plus every *other* peer's own_ip and lan_subnet - what a
# peer needs in its AllowedIPs to reach every other peer and every routed LAN,
# without routing its general internet traffic through the server too. Used
# by WGR_CLIENT_ROUTES=auto. Recomputed fresh each time, so it never goes
# stale as peers are added, removed or updated.
derive_auto_routes() {
    local exclude="$1" name own lan
    derive_tunnel_network
    while IFS= read -r name; do
        [[ -z "$name" || "$name" == "$exclude" ]] && continue
        own="$(peer_own_ip "$name")"
        [[ -n "$own" ]] && printf '%s\n' "$own"
        lan="$(peer_lan_subnet "$name")"
        [[ -n "$lan" ]] && printf '%s\n' "$lan"
    done < <(peer_names)
}

print_client_config() {
    local name="$1" dir="$PEERS_DIR/$1" endpoint own lan
    [[ -d "$dir" ]] || die "no such peer: $name (see '$PROG list')"
    own="$(peer_own_ip "$name")"
    [[ -n "$own" ]] || die "peer '$name' has no own_ip. Fix with: $PROG update $name --ip <address>"
    endpoint="$(derive_endpoint)"

    echo "# WireGuard client config for '$name'"
    echo "# Save as /etc/wireguard/wg0.conf on Linux, or import into the mobile app."
    echo
    echo "[Interface]"
    echo "PrivateKey = $(cat "$dir/private.key")"
    echo "Address = $own"
    echo "DNS = $(effective_dns "$name")"
    echo
    echo "[Peer]"
    echo "PublicKey = $(server_pubkey)"
    [[ -s "$dir/preshared.key" ]] && echo "PresharedKey = $(cat "$dir/preshared.key")"
    echo "Endpoint = $endpoint"
    local routes routes_setting
    routes_setting="${WGR_CLIENT_ROUTES:-$(derive_default_routes)}"
    if [[ "$routes_setting" == "auto" ]]; then
        routes="$(derive_auto_routes "$name" | sort -u | paste -sd, - | sed 's/,/, /g')"
    elif [[ -n "$routes_setting" ]]; then
        routes="$routes_setting"
    else
        routes="0.0.0.0/0, ::/0"
    fi
    echo "AllowedIPs = $routes"
    echo "PersistentKeepalive = 25"

    lan="$(peer_lan_subnet "$name")"
    if [[ -n "$lan" ]]; then
        echo
        note "note: '$name' routes $lan to the tunnel. Other peers reaching it need"
        note "      that subnet added to *their* AllowedIPs above, or the server"
        note "      alone can reach it while other peers cannot."
    fi

    if [[ "$endpoint" == "<"* ]]; then
        echo
        note "note: could not determine the endpoint; set dynu_hostname in your"
        note "      config file, or pass WGR_ENDPOINT=host:port, then re-run."
    fi
}

# --- Argument parsing for add/update -----------------------------------------

# Fills the caller's own_ip/lan_subnet/dns/clear_lan/clear_dns variables from
# "--lan X" / "--dns X" / "--ip X" / "--clear-lan" / "--clear-dns" in "$@".
parse_peer_flags() {
    own_ip=""; lan_subnet=""; dns=""; clear_lan=0; clear_dns=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --ip) own_ip="${2:-}"; shift 2 ;;
        --lan) lan_subnet="${2:-}"; shift 2 ;;
        --dns) dns="${2:-}"; shift 2 ;;
        --clear-lan) clear_lan=1; shift ;;
        --clear-dns) clear_dns=1; shift ;;
        *) die "unknown option: $1" ;;
        esac
    done
}

# --- Subcommands ------------------------------------------------------------

cmd_add() {
    local name="${1:-}" ip_raw="${2:-}"
    [[ -n "$name" && -n "$ip_raw" ]] ||
        die "usage: $PROG add <name> <own-ip> [--lan <subnet>] [--dns <ip>]"
    shift 2
    valid_peer_name "$name" ||
        die "peer name must be lowercase alphanumeric with - or _, max 32 chars"

    local dir="$PEERS_DIR/$name"
    [[ -e "$dir" ]] && die "peer '$name' already exists (remove it first, or pick another name)"

    local own_ip lan_subnet dns clear_lan clear_dns
    parse_peer_flags "$@"

    own_ip="$(normalise_own_ip "$ip_raw")"
    check_no_overlap "$own_ip" "" own_ip

    if [[ -n "$lan_subnet" ]]; then
        lan_subnet="$(normalise_lan_subnet "$lan_subnet")"
        check_no_overlap "$lan_subnet" "" lan_subnet
    fi

    if [[ -n "$dns" ]]; then
        valid_ip_address "$dns" || die "not a valid DNS address: $dns"
    fi

    ensure_server_key
    mkdir -p "$dir"
    chmod 700 "$dir"

    wg genkey > "$dir/private.key"
    wg pubkey < "$dir/private.key" > "$dir/public.key"
    wg genpsk > "$dir/preshared.key"
    printf '%s' "$own_ip" > "$dir/own_ip"
    [[ -n "$lan_subnet" ]] && printf '%s' "$lan_subnet" > "$dir/lan_subnet"
    [[ -n "$dns" ]] && printf '%s' "$dns" > "$dir/dns"
    chmod 600 "$dir"/*

    note "added peer '$name' ($own_ip$([[ -n "$lan_subnet" ]] && echo ", routing $lan_subnet"))"
    regen_tfvars
    note ""
    note "Apply the change with: ./wgr <platform> apply"
    note ""
    print_client_config "$name"
}

cmd_update() {
    local name="${1:-}"
    [[ -n "$name" ]] ||
        die "usage: $PROG update <name> [--ip <addr>] [--lan <subnet>] [--dns <ip>] [--clear-lan] [--clear-dns]"
    shift

    local dir="$PEERS_DIR/$name"
    [[ -d "$dir" ]] || die "no such peer: $name (see '$PROG list')"

    local own_ip lan_subnet dns clear_lan clear_dns
    parse_peer_flags "$@"
    [[ -n "$own_ip" || -n "$lan_subnet" || -n "$dns" || "$clear_lan" -eq 1 || "$clear_dns" -eq 1 ]] ||
        die "nothing to update: pass --ip, --lan, --dns, --clear-lan or --clear-dns"

    if [[ -n "$own_ip" ]]; then
        own_ip="$(normalise_own_ip "$own_ip")"
        check_no_overlap "$own_ip" "$name" own_ip
        printf '%s' "$own_ip" > "$dir/own_ip"
        note "updated '$name' own_ip -> $own_ip"
    fi

    if [[ "$clear_lan" -eq 1 ]]; then
        rm -f "$dir/lan_subnet"
        note "cleared '$name' lan_subnet"
    elif [[ -n "$lan_subnet" ]]; then
        lan_subnet="$(normalise_lan_subnet "$lan_subnet")"
        check_no_overlap "$lan_subnet" "$name" lan_subnet
        printf '%s' "$lan_subnet" > "$dir/lan_subnet"
        note "updated '$name' lan_subnet -> $lan_subnet"
    fi

    if [[ "$clear_dns" -eq 1 ]]; then
        rm -f "$dir/dns"
        note "cleared '$name' dns override"
    elif [[ -n "$dns" ]]; then
        valid_ip_address "$dns" || die "not a valid DNS address: $dns"
        printf '%s' "$dns" > "$dir/dns"
        note "updated '$name' dns -> $dns"
    fi

    chmod 600 "$dir"/* 2>/dev/null || true
    regen_tfvars
    note ""
    note "Apply the change with: ./wgr <platform> apply"
    note "This did not change '$name's keys - no client-side reconfiguration needed"
    note "unless you also changed --ip (its Address in the client config)."
}

cmd_client() {
    local name="${1:-}"
    [[ -n "$name" ]] || die "usage: $PROG client <name>"
    print_client_config "$name"
}

cmd_list() {
    local n=0 name own lan dns
    if [[ ! -f "$SERVER_KEY" ]]; then
        echo "No key store yet at $STORE"
        echo "Create one with: $PROG add <name> <own-ip>"
        return
    fi
    local default_dns default_routes
    default_dns="$(derive_default_dns)"
    default_routes="$(derive_default_routes)"
    printf '%-16s%s\n' "Key store:" "$STORE"
    printf '%-16s%s\n' "Server pubkey:" "$(server_pubkey)"
    printf '%-16s%s\n' "Endpoint:" "$(derive_endpoint)"
    printf '%-16s%s\n' "Default DNS:" "${default_dns:-(none set; peers fall back to 1.1.1.1)}"
    printf '%-16s%s\n' "Default routes:" "${default_routes:-(none set; peers fall back to full tunnel)}"
    printf '%-16s%s\n' "Generated:" "$TFVARS$([[ -f "$TFVARS" ]] || echo '  (missing - run '"$PROG"' regen)')"
    echo
    printf '%-20s %-18s %-18s %s\n' "PEER" "OWN IP" "LAN SUBNET" "DNS OVERRIDE"
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        own="$(peer_own_ip "$name")"
        if [[ -z "$own" ]]; then
            printf '%-20s %s\n' "$name" "(old format - fix with: $PROG update $name --ip <address>)"
        else
            lan="$(peer_lan_subnet "$name")"
            dns="$(peer_dns "$name")"
            printf '%-20s %-18s %-18s %s\n' "$name" "$own" "${lan:--}" "${dns:--}"
        fi
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
update)         shift; cmd_update "$@" ;;
client)         shift; cmd_client "$@" ;;
list|ls)        shift; cmd_list "$@" ;;
remove|rm)      shift; cmd_remove "$@" ;;
regen)          shift; regen_tfvars ;;
server-pubkey)  shift; server_pubkey ;;
rotate-server)  shift; cmd_rotate_server "$@" ;;
-h|--help|help|"") usage ;;
*)              die "unknown subcommand '$1' (try --help)" ;;
esac
