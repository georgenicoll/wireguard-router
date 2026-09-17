# ---------------------------------------------------------------------------
# DigitalOcean-specific settings. Copy this file next to your main config
# (the one WGR_CONFIG points at) and name it digitalocean.tfvars:
#
#   cp digitalocean.example.tfvars "$(dirname "$WGR_CONFIG")/digitalocean.tfvars"
#
# Credentials: export DIGITALOCEAN_TOKEN=...
# Run with:    ./wgr digitalocean apply
# ---------------------------------------------------------------------------

region       = "lon1"               # London. nyc1/nyc3, sgp1, etc. also available
droplet_size = "s-1vcpu-512mb-10gb" # cheapest droplet
image        = "ubuntu-24-04-x64"
# do_token   = "..."   # only if you would rather not use DIGITALOCEAN_TOKEN
