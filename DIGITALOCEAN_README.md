# DigitalOcean notes

Setup is simpler than AWS/Azure — no IAM policy or service principal dance.
See [digitalocean.example.tfvars](digitalocean.example.tfvars) and
[stacks/digitalocean/variables_platform.tf](stacks/digitalocean/variables_platform.tf)
for the available settings.

```bash
cp digitalocean.example.tfvars "$(dirname "$WGR_CONFIG")/digitalocean.tfvars"
export DIGITALOCEAN_TOKEN=...   # API token: Control Panel -> API -> Tokens
./wgr digitalocean apply
```

## `public_ipv4`/`public_ipv6` sometimes come back empty after `apply`

This is a known DigitalOcean-side timing issue, not something specific to
this repo's config: a droplet can report itself "active" before its network
info has fully replicated through their API, so
[`digitalocean_droplet.this.ipv4_address`](modules/platform/digitalocean/main.tf)
(and the IPv6 equivalent) can read back empty immediately after creation,
even though the droplet itself was created successfully. The DigitalOcean
Terraform provider has at least one merged fix for this exact race
([terraform-provider-digitalocean#1604](https://github.com/digitalocean/terraform-provider-digitalocean/pull/1604)),
for a related resource, so it's an acknowledged upstream issue rather than
something unique to how this project reads the attribute.

**Fix**: just re-run — this refreshes state and re-reads the droplet, which
by then almost always has its IP:

```bash
./wgr digitalocean apply    # no infrastructure changes expected
# or
./wgr digitalocean output
```

Deliberately not worked around with a polling/wait resource in this repo:
it would add a moving part (another provider, or a `local-exec` polling the
DO API) for what is, in practice, a few seconds' delay on first apply only.
