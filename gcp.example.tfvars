# ---------------------------------------------------------------------------
# GCP-specific settings. Copy this file next to your main config (the one
# WGR_CONFIG points at) and name it gcp.tfvars:
#
#   cp gcp.example.tfvars "$(dirname "$WGR_CONFIG")/gcp.tfvars"
#
# Credentials: gcloud auth application-default login
# Run with:    ./wgr gcp apply
#
# gcp_project is required - there is no sensible default for it.
# gcp_zone needs a zone (region + letter), not just a region, e.g.
# "europe-west2-a", not "europe-west2".
# e2-micro is free-tier eligible only in us-west1, us-central1 and us-east1.
# ---------------------------------------------------------------------------

gcp_project  = "my-project-id"
gcp_zone     = "us-central1-a"
machine_type = "e2-micro"
image        = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
network      = "default"
