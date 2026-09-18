# Azure setup

One-time steps for provisioning the WireGuard router on Azure. This covers
the Azure-side identity setup and the local credential setup in your private
config directory (the one `WGR_CONFIG` points at).

Unlike AWS/DigitalOcean, Azure has no "IAM user with an access key" concept.
The equivalent is a **service principal** (an app registration in Entra ID)
with a **role assignment** scoping what it can touch. See
[stacks/azure/variables_platform.tf:1](stacks/azure/variables_platform.tf#L1)
— credentials come from `az login` or the standard `ARM_*` service-principal
variables.

This stack creates its own resource group and everything inside it: a
resource group, VNet, subnet, public IP, network security group, NIC and one
Linux VM (see [modules/platform/azure/main.tf](modules/platform/azure/main.tf)).
The service principal needs subscription-level scope, because it has to be
able to create that resource group in the first place — but its *actions*
can still be tightly scoped to just the resource types this stack uses.

## 1. Create a custom role

Azure custom roles list exact `Actions` (control-plane operations) allowed
at given `AssignableScopes`. One gotcha worth knowing up front:
**`join/action` permissions**. Attaching a public IP or NSG to a NIC, or a
NIC to a subnet, requires an explicit `.../join/action` permission on the
*target* resource, separate from write access to the resource doing the
attaching — forgetting it gives an authorization error that looks unrelated
to what you're actually doing. It's included below.

Save this to a local file (e.g. `wireguard-router-role.json`), replacing
`<your-subscription-id>`:

```json
{
  "Name": "wireguard-router",
  "IsCustom": true,
  "Description": "Least-privilege role for the wireguard-router terraform stack",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/write",
    "Microsoft.Network/virtualNetworks/delete",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/write",
    "Microsoft.Network/virtualNetworks/subnets/delete",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/publicIPAddresses/write",
    "Microsoft.Network/publicIPAddresses/delete",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.Network/networkSecurityGroups/write",
    "Microsoft.Network/networkSecurityGroups/delete",
    "Microsoft.Network/networkSecurityGroups/join/action",
    "Microsoft.Network/networkSecurityGroups/securityRules/read",
    "Microsoft.Network/networkSecurityGroups/securityRules/write",
    "Microsoft.Network/networkSecurityGroups/securityRules/delete",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Network/networkInterfaces/write",
    "Microsoft.Network/networkInterfaces/delete",
    "Microsoft.Network/networkInterfaces/join/action",
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/write",
    "Microsoft.Compute/virtualMachines/delete",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/disks/read",
    "Microsoft.Compute/disks/write",
    "Microsoft.Compute/disks/delete"
  ],
  "NotActions": [],
  "DataActions": [],
  "NotDataActions": [],
  "AssignableScopes": [
    "/subscriptions/<your-subscription-id>"
  ]
}
```

Register it:

```bash
az role definition create --role-definition @wireguard-router-role.json
```

If `apply` later fails with an authorization error naming a specific action,
that's Azure telling you exactly what's missing — same as AWS's `AccessDenied`
messages — add it to `Actions` and re-run
`az role definition update --role-definition @wireguard-router-role.json`.

## 2. Create the service principal

```bash
az ad sp create-for-rbac --name "wireguard-router" \
  --role "wireguard-router" \
  --scopes "/subscriptions/<your-subscription-id>"
```

Custom roles can take up to a minute or two to propagate after step 1 —
if this errors with "role not found," wait and retry.

This outputs `appId`, `password` (client secret, shown once) and `tenant`.
Copy all three.

For a simpler but broader alternative, skip the custom role and pass
`--role "Contributor"` instead — the Azure equivalent of AWS's
`AmazonEC2FullAccess` shortcut. Fine for a personal subscription used only
for this project; less good if the subscription hosts other things.

## 3. Log the Azure CLI into the service principal

```bash
az login --service-principal -u <appId> -p <password> --tenant <tenant>
```

This is the Azure equivalent of `aws configure --profile` — rather than
exporting the client secret as a raw env var, the CLI caches the session
under `~/.azure` (local, not Dropbox-synced, refreshes itself). Terraform's
`azurerm` provider auto-detects the Azure CLI's current logged-in account
with no extra env vars needed.

Tradeoff: only one `az` account is "active" at a time on this machine — if
you also use `az` for your own Azure work, `az login` again as yourself to
switch back afterward, or `az account set` between subscriptions if it's the
same identity.

## 4. Copy the tfvars

```bash
cp azure.example.tfvars "$(dirname "$WGR_CONFIG")/azure.tfvars"
```

Set `azure_subscription_id` there — it's not a secret (unlike the client
secret from step 2), so it's fine in the Dropbox-synced file. Edit
`azure_location`/`vm_size` as needed — see
[azure.example.tfvars](azure.example.tfvars) for defaults (`uksouth`,
`Standard_B1ls`).

## 5. Init, plan, apply

```bash
./wgr azure init
./wgr azure plan
./wgr azure apply
```

Check the plan shows one resource group and its contents (VNet, subnet,
public IP, NSG, NIC, one VM) before applying.

## Troubleshooting

### `Terraform does not have the necessary permissions to register Resource Providers`

By default the `azurerm` provider tries to auto-register every resource
provider it supports (far more than this stack uses), which the scoped
service principal correctly isn't granted rights for. Already handled in
[stacks/azure/versions.tf](stacks/azure/versions.tf) via
`resource_provider_registrations = "none"` — if you see this, make sure
you're on a version of this repo that includes that setting.

### `MissingSubscriptionRegistration: The subscription is not registered to use namespace 'Microsoft.Network'`

Opting out of auto-registration (above) means the providers this stack
actually needs must already be registered on the subscription — true for
subscriptions with prior real use, not always true for new/lightly-used
ones. Register them once using your own admin login, not the scoped service
principal (which correctly can't do this):

```bash
az login                          # your own admin/console identity
az account set --subscription <your-subscription-id>

az provider register --namespace Microsoft.Network
az provider register --namespace Microsoft.Compute
az provider register --namespace Microsoft.Resources
```

Registration is asynchronous — check status with:

```bash
az provider show --namespace Microsoft.Network --query registrationState -o tsv
```

Wait until that (and the other two) say `Registered` (can take a minute or
two), then switch back to the service principal and retry:

```bash
az login --service-principal -u <appId> -p <password> --tenant <tenant>
./wgr azure apply
```

### `SkuNotAvailable` / `NotAvailableForSubscription` on `vm_size`

Unlike AWS's transient `InsufficientInstanceCapacity`, Azure fails this
immediately rather than retrying - but it can be a persistent, not
transient, restriction. The older **v1** `Bs` family (`B1ls`, `B1s`,
`B1ms`, ...) is `NotAvailableForSubscription` on some subscription
types/regions even when the family has vCPU quota (check with
`az vm list-usage --location <region> -o table` - a nonzero `Standard BS
Family vCPUs` limit does *not* guarantee v1 SKUs are actually offered to
you). The default `vm_size` here (`Standard_B2ts_v2`) uses the newer **v2**
`B`-series instead, which doesn't have this restriction.

To check what's actually available to your subscription in a region:

```bash
az vm list-skus --location uksouth --all \
  --query "[?starts_with(name,'Standard_B') && contains(name,'v2')].{Name:name, Restrictions:restrictions[0].reasonCode}" -o table
```

Any row with no `Restrictions` value is usable.

### `OperationNotAllowed: ... exceeding approved standardBsv2Family Cores quota`

Different from the restriction above: the SKU itself is offered to you, but
the family's vCPU quota in that region is `0` until Azure grants it -
routine for a subscription that's never deployed that family before. Check
current quota:

```bash
az vm list-usage --location uksouth \
  --query "[?contains(name.value,'Bsv2')].{Name:name.value, Current:currentValue, Limit:limit}" -o table
```

Request an increase (2 cores covers `Standard_B2ts_v2`) using your own
admin login, not the scoped service principal (which correctly can't do
this - `az login` as yourself first, then `az login --service-principal ...`
again afterwards to switch back):

```bash
az login   # your own admin/console identity
az quota create \
  --resource-name standardBsv2Family \
  --scope "/subscriptions/<your-subscription-id>/providers/Microsoft.Compute/locations/uksouth" \
  --limit-object value=2 \
  --resource-type dedicated
```

If that errors with `MissingRegistrationForResourceProvider ... Microsoft.Quota`,
register it too (as yourself, same as the `Microsoft.Network`/`Microsoft.Compute`
registration above) and retry:

```bash
az provider register --namespace Microsoft.Quota
az provider show --namespace Microsoft.Quota --query registrationState -o tsv
```

Check approval status:

```bash
az quota show \
  --resource-name standardBsv2Family \
  --scope "/subscriptions/<your-subscription-id>/providers/Microsoft.Compute/locations/uksouth"
```

Small requests like this are often approved within minutes. If you'd rather
not wait, a size in a family that already has quota (e.g.
`Standard_D2s_v3`, in the `DSv3` family) will deploy immediately - bigger
and pricier than the default burstable tier, but zero setup.
