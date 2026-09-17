# ---------------------------------------------------------------------------
# Linode-specific settings. Copy this file next to your main config (the one
# WGR_CONFIG points at) and name it linode.tfvars:
#
#   cp linode.example.tfvars "$(dirname "$WGR_CONFIG")/linode.tfvars"
#
# Credentials: export LINODE_TOKEN=...
# Run with:    ./wgr linode apply
# ---------------------------------------------------------------------------

region        = "eu-west"     # London. us-east = Newark, ap-south = Singapore
instance_type = "g6-nanode-1" # cheapest plan, 1 GB
image         = "linode/ubuntu24.04"
linode_token  = "..."   # only if you would rather not use LINODE_TOKEN
