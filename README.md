# wireguard-router

OpenTofu configuration that provisions a small Ubuntu server on a cloud
provider and turns it into a hardened WireGuard endpoint that registers its own
public IP with [Dynu](https://www.dynu.com/) dynamic DNS.

The server is designed to be disposable: destroy it, recreate it on a different
provider, and your clients keep working because they connect to the dynamic
hostname rather than an IP address.

## TL;DR: setting up a new server and peers

Start to finish, on Linode. Swap `linode` for `aws`, `gcp` or `azure`
throughout; only the credentials and provider-specific settings in step 3
actually differ.

**1. Install the tools.**

```bash
sudo apt install wireguard-tools          # wg genkey / genpsk / pubkey
tofu version                              # https://opentofu.org/docs/intro/install/
```

**2. Create an SSH key, if you do not already have one.** The server allows
key-based login only, so without this you cannot get in.

```bash
ssh-keygen -t ed25519 -C "wireguard-router"
cat ~/.ssh/id_ed25519.pub                 # paste into ssh_public_key in step 3
```

**3. Create your config file and point the tooling at it.**

```bash
cp config.example.tfvars ~/private/wireguard-router.tfvars
$EDITOR ~/private/wireguard-router.tfvars

export WGR_CONFIG=~/private/wireguard-router.tfvars
export WGR_STATE_DIR=~/private/wireguard-router-state   # keeps secrets out of the repo
export LINODE_TOKEN=...                                 # cloud credentials
```

The values you must fill in: `ssh_public_key`, `dynu_hostname`, `dynu_api_key`,
and `region` (or the equivalent location setting for another provider).
Everything else has a working default, including
non-default `ssh_port` (58022) and `wireguard_port` (47654). Leave the
WireGuard key settings alone — step 5 generates them.

Put the three `export` lines in your shell profile or a direnv `.envrc`, or
you will be re-typing them every session.

**4. Decide your tunnel addresses.** These are private addresses *inside* the
VPN, unrelated to any real network. The default subnet is `10.66.66.0/24`, and
the server takes `.1`:

| Host | Tunnel address | Set where |
| --- | --- | --- |
| the server | `10.66.66.1/24` | `wireguard_address` (default, fine as-is) |
| first peer | `10.66.66.2` | `wg-peer.sh add` |
| second peer | `10.66.66.3` | `wg-peer.sh add` |

Give every peer its own address. The script refuses duplicates.

**5. Generate the server key and your peers.** One command per device:

```bash
./scripts/wg-peer.sh add laptop 10.66.66.2
./scripts/wg-peer.sh add phone  10.66.66.3
```

Each prints a ready-to-use client config, and writes the keys into the store
beside your config file. The server key is created once, on the first `add`.

**6. Create the server.**

```bash
./wgr linode init
./wgr linode apply
```

**7. Wait for it to finish configuring itself.** `apply` returns before
cloud-init has finished, which takes a few minutes.

```bash
ssh -p 58022 wgadmin@$(./wgr linode output -raw public_ipv4)
sudo cloud-init status --wait
sudo wg show                              # should list your peers
journalctl -u dynu-update.service -n 20   # should show "-> <your IP> (good ...)"
```

**8. Connect a client.** Reprint a config whenever you need it:

```bash
./scripts/wg-peer.sh client laptop
```

On Linux, save it as `/etc/wireguard/wg0.conf` and bring it up:

```bash
sudo install -m 600 /dev/stdin /etc/wireguard/wg0.conf < <(./scripts/wg-peer.sh client laptop)
sudo wg-quick up wg0
ping 10.66.66.1                           # the server, inside the tunnel
```

For a phone, render the same config as a QR code and scan it from the
WireGuard app (`sudo apt install qrencode`):

```bash
./scripts/wg-peer.sh client phone | qrencode -t ansiutf8
```

**9. Adding a peer later.** Same command, then re-apply so the server accepts it:

```bash
./scripts/wg-peer.sh add tablet 10.66.66.4
./wgr linode apply
```

This never touches the server key, so existing clients are unaffected.

**10. Tear it down** when you no longer need it. The key store survives, so
recreating later — on any provider — keeps every client working:

```bash
./wgr linode destroy
```

## Design

The provider-specific surface is deliberately tiny. Everything that actually
configures the machine lives in one cloud-agnostic module:

| Path | Role |
| --- | --- |
| `modules/node-config/` | Renders the whole cloud-init document: WireGuard, Dynu client, firewall, SSH hardening. **No provider-specific logic.** |
| `modules/platform/<cloud>/` | Creates a VM and opens two ports. Nothing else. All four expose an identical input/output interface. |
| `stacks/<cloud>/` | ~40 lines wiring the two modules together, plus the provider block. |
| `shared/variables_common.tf` | The cloud-agnostic input contract, symlinked into every stack. |
| `shared/outputs_common.tf` | Outputs, symlinked into every stack. |

Because the shared files are symlinks and the platform modules share one
interface, switching cloud is a one-word change and the resulting server is
byte-for-byte identically configured.

## Prerequisites

- [OpenTofu](https://opentofu.org/docs/intro/install/) >= 1.6
- `wireguard-tools` locally, to generate keys (`sudo apt install wireguard-tools`)
- An account with the cloud provider you intend to use
- A Dynu account with a hostname created, and an API key from
  Control Panel -> API Credentials

## One-time setup

**1. Create your config file, outside this repository.**

```bash
cp config.example.tfvars ~/private/wireguard-router.tfvars
$EDITOR ~/private/wireguard-router.tfvars
export WGR_CONFIG=~/private/wireguard-router.tfvars
```

It holds your Dynu password, so it must live outside the repo. `.gitignore`
refuses to track `*.tfvars` as a second line of defence. (Your WireGuard keys
live in the key store, not in this file.)

Optionally keep state outside the repo too — it also contains those secrets:

```bash
export WGR_STATE_DIR=~/private/wireguard-router-state
```

**2. Generate your WireGuard keys and first peer.** See
[Generating WireGuard configuration](#generating-wireguard-configuration) below.

```bash
./scripts/wg-peer.sh add laptop 10.66.66.2
```

**3. Provide cloud credentials.** For Linode:

```bash
export LINODE_TOKEN=...   # or set linode_token in your config file
```

## Environment variables

| Variable | Purpose |
| --- | --- |
| `WGR_CONFIG` | Path to your private `.tfvars` file. Required for `plan`/`apply`/`destroy`. |
| `WGR_KEYS` | Key store location. Defaults to `wireguard-router-keys` beside `WGR_CONFIG`. |
| `WGR_STATE_DIR` | Keep state outside the repo, one file per platform. Recommended. |
| `WGR_ENDPOINT` | Override the `Endpoint` written into client configs. |
| `WGR_CLIENT_ROUTES` | Override client `AllowedIPs`. Default `0.0.0.0/0, ::/0` (full tunnel). |
| `WGR_CLIENT_DNS` | Override client `DNS`. Default `1.1.1.1`. |

Worth putting the first three in your shell profile or a direnv `.envrc`.

## Usage

```bash
./wgr linode init
./wgr linode plan
./wgr linode apply
./wgr linode output
./wgr linode destroy
```

`apply` returns before the server has finished configuring itself; cloud-init
continues for a few minutes. To watch it:

```bash
ssh -p 58022 wgadmin@$(./wgr linode output -raw public_ipv4)
sudo cloud-init status --wait
sudo wg show
systemctl status dynu-update.timer
journalctl -u dynu-update.service -n 20
```

Point clients at the dynamic hostname, not the IP:

```bash
./wgr linode output -raw wireguard_endpoint    # e.g. yourname.freeddns.org:47654
```

## Generating WireGuard configuration

Keys are created with the standard `wireguard-tools` (`wg genkey`, `wg genpsk`,
`wg pubkey`) and kept in a **key store** outside this repository.
`scripts/wg-peer.sh` manages that store and writes a tfvars file from it, which
`./wgr` then passes to OpenTofu automatically. You never paste a key by hand,
and you never edit the generated file.

```bash
./scripts/wg-peer.sh add laptop 10.66.66.2     # new peer + printed client config
./scripts/wg-peer.sh client laptop             # reprint that client config later
./scripts/wg-peer.sh list                      # peers, server pubkey, endpoint
./scripts/wg-peer.sh remove laptop             # revoke a peer (prompts first)
./scripts/wg-peer.sh regen                     # rebuild the tfvars from the store
./scripts/wg-peer.sh server-pubkey             # print the server public key
./scripts/wg-peer.sh rotate-server --force     # new server key; breaks all clients
```

After any change that alters the store, apply it to the server:

```bash
./wgr linode apply
```

### Where the keys live

The store location is `$WGR_KEYS`, defaulting to a `wireguard-router-keys`
directory alongside your `WGR_CONFIG` file. Directories are created `0700` and
every file `0600`.

```
~/private/wireguard-router-keys/
├── server.key                      # server private key, created once
├── peers/
│   └── laptop/
│       ├── private.key             # retained, so client configs are reprintable
│       ├── public.key
│       ├── preshared.key
│       └── allowed_ips             # tunnel addresses this peer may use
└── wireguard.generated.tfvars      # GENERATED - consumed automatically by ./wgr
```

Back this directory up. It is the only copy of your keys, and losing
`server.key` means reconfiguring every client.

### How it reaches OpenTofu

`wgr` passes two `-var-file` flags: your main config first, then the generated
file. Later files win in OpenTofu, so the store is authoritative for
`wireguard_private_key` and `wireguard_peers`. That is why those two settings
are absent from `config.example.tfvars` — if you do set them there, `wgr`
prints a warning that the generated file is overriding you.

```
tofu ... -var-file=<your config> -var-file=<store>/wireguard.generated.tfvars
```

The generated file is plain HCL, so you can always read exactly what tofu will
receive. If you would rather not use the store at all, delete the generated file
and set `wireguard_private_key` and `wireguard_peers` in your own config by
hand; nothing else depends on the script.

### Adding more peers safely

`add` creates `server.key` **only when it is absent**, so adding your tenth peer
cannot rotate the server key out from under the first nine. Rotating is possible
but has to be asked for explicitly with `rotate-server --force`, which then
lists the clients you need to reissue.

Each peer needs its own tunnel address. `add` refuses a name that already
exists, refuses an address already assigned to another peer, and validates
addresses numerically — `10.66.66.256` and `999.1.1.1` are rejected rather than
quietly accepted.

Client configs are rendered with `Endpoint` filled in from `dynu_hostname` and
`wireguard_port` in your config file, `AllowedIPs = 0.0.0.0/0, ::/0` for a full
tunnel, and `DNS = 1.1.1.1`. Override any of them per invocation:

```bash
WGR_ENDPOINT=host:51820 \
WGR_CLIENT_ROUTES="10.66.66.0/24" \
WGR_CLIENT_DNS=9.9.9.9 \
  ./scripts/wg-peer.sh client laptop
```

`WGR_CLIENT_ROUTES` is the useful one: the default sends *all* the client's
traffic through the server, whereas `10.66.66.0/24` gives a split tunnel where
only traffic between peers is routed.

### A note on secrets

The server's private key necessarily ends up in OpenTofu state, because it has
to be delivered to the machine. The key store does not change that — it just
stops the key living in a file you hand-edit. Treat state as sensitively as the
store itself, which is what `WGR_STATE_DIR` is for.

## Dynu credentials

Two authentication methods are supported. Set **one** of them; the plan fails
if you set both or neither.

### API key (recommended)

```hcl
dynu_api_key = "..."     # Control Panel -> API Credentials
```

This uses Dynu's v2 REST API. The updater resolves your hostname to its domain
id via `GET /v2/dns/getroot/<hostname>`, reads the current domain object, and
`POST`s it back with only `ipv4Address` changed — so TTL, IPv6, wildcard and
DNSSEC settings are left exactly as they were. It needs `jq` on the server,
which is installed for you.

Prefer this. An API key is revocable independently of your password and cannot
be used to log into the control panel, which matters because this credential
lives on a disposable cloud VM.

### Username and password (legacy)

```hcl
dynu_username = "..."
dynu_password = "..."
```

This uses the older dyndns2 `/nic/update` endpoint, which **does not accept an
API key** — that is the whole reason both paths exist. It is simpler and needs
no `jq`, but the credential is your account password, so a leak exposes the
whole account.

### Caveat: hostnames below your own domain

The API-key path manages a Dynu hostname *directly* (for example
`yourname.freeddns.org`). If `dynu_hostname` is a sub-domain of a domain you
own — `vpn.example.com` — then `getroot` resolves to `example.com`, and the
address belongs on a record beneath it rather than on the domain itself. Rather
than repoint the wrong name, the updater detects this and fails with an
explanation. Use the username/password method for that case, since it updates
by hostname.

## Switching cloud provider

Change one word. The same config file drives every stack:

```bash
./wgr linode destroy
./wgr gcp init
./wgr gcp apply
```

Per-provider extras are the only additional work:

| Provider | Credentials | Extra required variable | Cheapest size used |
| --- | --- | --- | --- |
| Linode | `LINODE_TOKEN` | — | `g6-nanode-1` |
| AWS | `AWS_PROFILE` / standard SDK env vars | — | `t4g.nano` (arm64) |
| GCP | `gcloud auth application-default login` | `gcp_project` | `e2-micro` |
| Azure | `az login` | — (`azure_subscription_id` optional) | `Standard_B1ls` |

Each stack declares only its own platform variables, so remove other providers'
blocks from your config file (or keep separate files per provider) — OpenTofu
rejects variables a stack does not declare.

Because the endpoint is a dynamic hostname and the Dynu client re-registers on
boot, clients follow the server to its new provider with no config change. Only
the server's WireGuard public key must stay the same, which it does as long as
`wireguard_private_key` is unchanged.

## What gets configured on the server

**WireGuard**
- Confirms the running kernel actually provides the `wireguard` module, and
  fails provisioning loudly if it does not
- Enables IPv4/IPv6 forwarding via `/etc/sysctl.d/`
- NAT and forwarding rules are applied by `/usr/local/sbin/wg-nat`, which
  discovers the upstream interface from the default route at runtime — this is
  why the identical config works on `eth0`, `ens4` and `enX0` alike
- Clamps TCP MSS to the path MTU, avoiding the classic "SSH works but web pages
  hang" symptom inside a tunnel
- Listens on a non-default UDP port

**Dynamic DNS**
- Authenticates with a Dynu **API key** against their v2 REST API. The key is
  revocable on its own and, unlike your account password, does not grant
  control-panel access if the server is compromised
- Updates preserve the domain's other settings: the current record is read,
  only the IPv4 address is changed, and the object is sent back
- A systemd timer runs `/usr/local/sbin/dynu-update` every 5 minutes and at boot
- The public IP is cached, so an unchanged address makes no API call, but an
  update is forced at least daily so the hostname is not reaped as stale
- Credentials live in `/etc/dynu/dynu.env`, mode `0600`
- A rejected update exits non-zero and is visible in `journalctl`

**Access and hardening**
- Password authentication and root login disabled; one sudo user with one key
- `AuthenticationMethods publickey`, `MaxAuthTries 3`, no TCP/agent forwarding
- sshd on a non-default port. Ubuntu 24.04 socket-activates sshd, so both
  `sshd_config` and the `ssh.socket` unit are overridden
- Two independent firewall layers: the cloud provider's, and `ufw` on the host.
  Default-deny inbound; only the SSH and WireGuard ports are open
- `fail2ban` configured for the non-default port using the systemd journal
  backend, and unattended security upgrades enabled

## Notes

- Your WireGuard keys live in the key store, not in your config file — see
  [Generating WireGuard configuration](#generating-wireguard-configuration).
  Back that directory up; `server.key` should be treated as permanent, because
  changing it invalidates every client config.
- Narrow `allowed_ssh_cidrs` to your own network if you have a static IP. The
  default of `0.0.0.0/0` is safe but noisy.
- `image` defaults to Ubuntu 24.04 LTS. Bump it in your config file to move to a
  newer release; the module pins nothing to that version.
- The state file contains secrets. Keep it private (see `WGR_STATE_DIR`).
- Adding a fifth provider means writing one module under `modules/platform/`
  with the same four inputs and four outputs, and copying a stack directory.

## Layout

```
wgr                          driver script: ./wgr <cloud> <tofu command>
config.example.tfvars        template for your private config file
scripts/wg-peer.sh           key store + client config management
shared/                      cloud-agnostic variables and outputs (symlinked)
modules/node-config/         all server configuration, provider-independent
modules/platform/{linode,aws,gcp,azure}/
stacks/{linode,aws,gcp,azure}/
```
