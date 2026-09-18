# ---------------------------------------------------------------------------
# Azure-specific settings. Copy this file next to your main config (the one
# WGR_CONFIG points at) and name it azure.tfvars:
#
#   cp azure.example.tfvars "$(dirname "$WGR_CONFIG")/azure.tfvars"
#
# Credentials: az login (or the standard ARM_* service-principal variables)
# Run with:    ./wgr azure apply
# ---------------------------------------------------------------------------

azure_location        = "uksouth"
vm_size               = "Standard_B2ts_v2" # cheap burstable size, 1 GiB. The
                                            # older v1 Bs family (B1ls etc.)
                                            # can be NotAvailableForSubscription
                                            # - see AZURE_SETUP.md.
azure_subscription_id = "..."           # or export ARM_SUBSCRIPTION_ID
