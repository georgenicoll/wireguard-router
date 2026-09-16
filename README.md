# wireguard-router

OpenTofu configuration that provisions a small Ubuntu server on a cloud
provider and turns it into a hardened WireGuard endpoint that registers its own
public IP with [Dynu](https://www.dynu.com/) dynamic DNS.

The server is designed to be disposable: destroy it, recreate it on a different
provider, and your clients keep working because they connect to the dynamic
hostname rather than an IP address.

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
- A Dynu account with a hostname created

## One-time setup

**1. Generate WireGuard keys.**

```bash
./scripts/genkeys.sh laptop 10.66.66.2
```

This prints a server private key and peer block for your config file, plus a
ready-to-use client config. Keys are printed once and never written to disk.

**2. Create your config file, outside this repository.**

```bash
cp config.example.tfvars ~/private/wireguard-router.tfvars
$EDITOR ~/private/wireguard-router.tfvars
export WGR_CONFIG=~/private/wireguard-router.tfvars
```

It holds your WireGuard private key and Dynu password, so it must live outside
the repo. `.gitignore` refuses to track `*.tfvars` as a second line of defence.

Optionally keep state outside the repo too — it also contains those secrets:

```bash
export WGR_STATE_DIR=~/private/wireguard-router-state
```

**3. Provide cloud credentials.** For Linode:

```bash
export LINODE_TOKEN=...   # or set linode_token in your config file
```

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

- `wireguard_private_key` should be treated as permanent. Changing it
  invalidates every client config.
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
scripts/genkeys.sh           WireGuard key + client config generator
shared/                      cloud-agnostic variables and outputs (symlinked)
modules/node-config/         all server configuration, provider-independent
modules/platform/{linode,aws,gcp,azure}/
stacks/{linode,aws,gcp,azure}/
```
