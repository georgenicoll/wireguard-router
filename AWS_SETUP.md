# AWS setup

One-time steps for provisioning the WireGuard router on AWS EC2. This covers
the AWS-side IAM setup and the local credential/environment setup in your
private config directory (the one `WGR_CONFIG` points at).

Unlike DigitalOcean/Linode, the AWS provider takes no token variable in
`aws.tfvars` — it authenticates via the standard AWS SDK credential chain
(`AWS_PROFILE` or the raw `AWS_*` env vars). See
[stacks/aws/variables_platform.tf](stacks/aws/variables_platform.tf).

## 1. Create a dedicated IAM user

In the AWS console (or CLI), using your root/admin account:

- IAM → Users → Create user, e.g. `wireguard-router`
- No console access — programmatic access only (access keys)

Don't attach a broad managed policy like `AmazonEC2FullAccess` unless you
want the simplicity; the scoped policy below covers exactly what this stack
does: look up a VPC/subnet/AMI, and manage one security group and one
instance (see [modules/platform/aws/main.tf](modules/platform/aws/main.tf)).

### Policy document

Create a customer-managed policy (IAM → Policies → Create policy → JSON) and
attach it only to the `wireguard-router` user:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadOnlyDescribe",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CreateSecurityGroup",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:DeleteSecurityGroup"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RunAndTerminateInstance",
      "Effect": "Allow",
      "Action": [
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyInstanceMetadataOptions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "TagOnCreate",
      "Effect": "Allow",
      "Action": [
        "ec2:CreateTags"
      ],
      "Resource": "*"
    }
  ]
}
```

`ec2:Describe*` covers the read-only lookups the provider needs (VPC,
subnet, AMI, instance, security group, network interface, tags, ...) without
enumerating each one and re-editing the policy every time terraform's
internal diffing/cleanup logic turns out to need one more. It's read-only,
so the risk is information disclosure about your account's EC2 state, not
mutation.

`Resource: "*"` is used throughout because `RunInstances` needs to reach
VPC/subnet/AMI/security-group ARNs that don't exist yet, and most EC2
actions don't support resource-level ARN scoping at all. This is fine for a
dedicated user with no other purpose. If you want to tighten it further, add
a `Condition` restricting `aws:RequestedRegion` to your region.

## 2. Generate an access key

IAM → Users → `wireguard-router` → **Security credentials** tab → **Create
access key** → choose **"Command Line Interface (CLI)"** as the use case.
The secret is shown once — copy both values.

Considered and rejected: `aws login` / IAM Identity Center SSO instead of a
static key. It authenticates as your own console identity rather than this
scoped-down user, which would hand terraform whatever broad permissions your
main console login has — defeating the point of the dedicated policy above.
Static keys on a single-purpose least-privilege user are the better fit here.

## 3. Store the key as a named AWS CLI profile

Do **not** put these in `aws.tfvars` — that file lives in a Dropbox-synced
private directory, and AWS secret keys are more sensitive than a quick token
(unlike DigitalOcean's `do_token`, there's no variable in this repo for AWS
keys anyway). Use the standard AWS credentials file instead, which stays
local and out of any synced folder:

```bash
aws configure --profile wireguard-router
# AWS Access Key ID: ...
# AWS Secret Access Key: ...
# Default region: eu-west-2
# Default output format: (leave blank)
```

This writes to `~/.aws/credentials` and `~/.aws/config` (mode `600`, your
user only). Alternatives if you'd rather not go through the interactive
prompt:

```bash
# non-interactive
aws configure set aws_access_key_id AKIA... --profile wireguard-router
aws configure set aws_secret_access_key ... --profile wireguard-router
aws configure set region eu-west-2 --profile wireguard-router
```

or edit `~/.aws/credentials` directly:

```ini
[wireguard-router]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

## 4. Point your shell at the profile

The environment needs `AWS_PROFILE=wireguard-router` set, alongside
`WGR_CONFIG`/`WGR_STATE_DIR`, whenever you run `wgr`. This is just the
profile name, not a secret — the actual key material stays in
`~/.aws/credentials`, never in the repo or your private config directory.

## 5. Copy the tfvars

```bash
cp aws.example.tfvars "$(dirname "$WGR_CONFIG")/aws.tfvars"
```

Edit `aws_region` / `instance_type` / `architecture` as needed — see
[aws.example.tfvars](aws.example.tfvars) for defaults (`eu-west-2`,
`t4g.nano`, `arm64`).

## 6. Init, plan, apply

```bash
./wgr aws init
./wgr aws plan
./wgr aws apply
```

Check the plan shows exactly one security group and one instance before
applying.

## Troubleshooting: apply seems to hang on `aws_instance.this: Creating...`

This can mean AWS returned `InsufficientInstanceCapacity` for the AZ
`subnet_id` landed in — cheap burstable types like `t4g.nano` can be short on
spare capacity in a specific AZ at a given moment. The AWS provider retries
this automatically with backoff, which is what makes it look like a hang
rather than an error; `max_retries = 3` on the provider
([stacks/aws/versions.tf](stacks/aws/versions.tf)) caps that so it fails
within about a minute instead.

When `subnet_id` is left empty in `aws.tfvars`, the module picks a random
subnet/AZ ([modules/platform/aws/main.tf](modules/platform/aws/main.tf)) so a
retry is likely to land somewhere else. The pick is stored in state and
stays fixed across a plain re-`apply`, so force a reshuffle by destroying and
re-applying:

```bash
./wgr aws destroy
./wgr aws apply
```

If you'd rather pin a specific AZ yourself, set `subnet_id` explicitly in
`aws.tfvars` (list candidates with `aws ec2 describe-subnets --region
<region> --filters Name=default-for-az,Values=true`).
