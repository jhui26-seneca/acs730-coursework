# Lab 5 - Terraform Introduction and Reliable CI

One Terraform configuration describes a complete public network and a web server. The `use_localstack` variable decides whether it targets real AWS or LocalStack, a local AWS emulator. Every pull request validates it against LocalStack in CI, with no AWS credentials in the pipeline.

## Why not plan and apply against real AWS on every pull request

Running `terraform plan` and `apply` against real AWS on every pull request is slow, because a VPC, a gateway and an instance take minutes to create and destroy where LocalStack takes seconds. It is expensive, because every run creates billable resources, and a forgotten teardown or a NAT gateway keeps charging whether it is used or not. It is flaky, because the result depends on the cloud account, its quotas and its credentials, not just on the change being reviewed.

In an AWS Academy account all three get worse. The credentials expire when the lab session ends, so a check that ran green at noon fails with ExpiredToken in the evening for reasons unrelated to the code. There is a fixed $50 credit shared with every other lab, and IAM is locked down. Applying from Actions would also need a long-lived access key stored in GitHub secrets, which can leak and must be rotated, and because IAM writes are denied in Academy it could not be scoped down to only what Terraform needs, so the only key that would work is a broad one. A required check that depends on all of that would block merges at random. LocalStack gives a fast, free and repeatable answer to the question CI should ask, "is this configuration coherent?", while the real deploy happens deliberately, later. A green LocalStack run does not prove the deploy will work: LocalStack does not enforce IAM and never boots user_data.

## Why for_each here and count there

The subnets use `for_each` because they are distinct things with stable names, and the map key becomes part of each address (`aws_subnet.public["a"]`). Terraform matches state to configuration by address, so a key is an identity. In Experiment 1, with three subnets `a`, `b` and `c`, removing `b` planned **0 to add, 0 to change, 2 to destroy**: subnet `b` and its route table association, with `a` and `c` untouched.

The same subnets with `count` are a trap. Their addresses are positions (`[0]`, `[1]`, `[2]`), so removing the middle CIDR moves the third CIDR down into slot `[1]`. Terraform compares `public[1]` in the state with a different CIDR in the configuration, and the plan was **2 to add, 0 to change, 4 to destroy**: it replaced subnet `[1]` and its association and destroyed `[2]` and its association, all to remove one subnet. On real AWS, anything running in the replaced subnet would have been destroyed with it.

The bucket uses `count` because its input is a yes/no about one resource: `create_bucket` gives exactly two plans, bucket or no bucket, and there is no key to keep stable. In short, `count` answers "how many", and `for_each` answers "which ones".

## Terraform files

| File | Creates / changes | Notes |
|---|---|---|
| `versions.tf` | Nothing | Pins Terraform `~> 1.10` and the AWS provider `~> 5.0`; local state on purpose |
| `providers.tf` | Nothing | One AWS provider; LocalStack endpoints, dummy keys and `s3_use_path_style` only when `use_localstack = true` |
| `variables.tf` | Nothing | Every variable typed and described; validation on `aws_region`, `vpc_cidr`, `instance_type` |
| `network.tf` | VPC `acs730-lab5-vpc`, subnets `-subnet-a`/`-b` (for_each), internet gateway, route table + associations, security group `acs730-lab5-sg` (dynamic ingress), bucket (count-gated) | Data sources: availability zones, caller identity |
| `compute.tf` | Instance `acs730-lab5-web` with user_data | AMI data source; explicit `depends_on` on the route table associations |
| `outputs.tf` | Nothing | `vpc_id`, `subnet_ids`, `web_public_ip`, `web_url`, `provider_target`, `bucket_name` |
| `localstack.tfvars` | Nothing | Switches the run to LocalStack |

Deletes: everything above, with `terraform destroy -var-file=localstack.tfvars`.

## Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/start-localstack.sh` | Docker container `acs730-lab5-localstack` (image `localstack/localstack:3.8`, port 4566); waits until healthy | Nothing (replaces a stopped container of the same name) | None | Workstation |
| `scripts/stop-localstack.sh` | Nothing | The `acs730-lab5-localstack` container and every emulated resource in it | None | Workstation |
| `scripts/check-teardown.sh` | `evidence/describe-vpcs-after-destroy.json` | Nothing | None. Run after `terraform destroy` | Workstation |

## Workflow

| File | Creates / changes | Triggered by |
|---|---|---|
| `.github/workflows/lab5-ci.yml` | Nothing in AWS. Job `gates`: `fmt -check`, `init -backend=false`, `validate`. Job `localstack` (needs `gates`): plan, apply, output check and destroy against a LocalStack service container | Pull request or push to `main` touching `lab5/**` or the workflow file |

## Evidence

- `evidence/caller-identity.png` - workstation identity at the start of the lab
- `evidence/describe-vpcs-after-destroy.json` - no `acs730-lab5-vpc` left after destroy
- `evidence/ci-run-green.txt` - green run with both jobs
- `evidence/ci-run-red.txt`, `evidence/pr-blocked.json`, `evidence/required-check-blocked.png` - the deliberate break, with the merge blocked
- `evidence/ci-runs.txt` - the run history: green, red, green

## Experiments

Each experiment ran on a throwaway copy of this configuration (the scripts and their raw output are in my private repository), and every change was undone afterwards. Experiments 1, 2 and 4 ran against LocalStack; Experiment 5 only planned against the real account; Experiment 3 ran in CI on the rework pull request.

### 1. Swap for_each for count on the subnets

**What happened:** With `count` over three CIDRs, removing the middle one planned 2 to add, 0 to change, 4 to destroy: `aws_subnet.public[1]` and its association were replaced, and `[2]` and its association were destroyed "because index [2] is out of range for count". With `for_each` over the keys `a`, `b` and `c`, removing `b` planned 0 to add, 0 to change, 2 to destroy, and only `["b"]` and its association were touched.

**Why:** `count` addresses are positions, so deleting from the middle shifts every later element and Terraform sees changes where nothing changed; `for_each` addresses are keys, so removing one key affects only that key. That is why the subnets use `for_each`.

### 2. Delete the depends_on

**What happened:** With the `depends_on` commented out, the plan against LocalStack was identical - 10 to add, 0 to change, 0 to destroy, with the same resources and actions. The only difference was in `terraform graph`: the edges from `aws_instance.web` to the route table associations went from 1 to 0.

**Why:** The instance references its subnet and security group, but nothing in it references the route table association, so without `depends_on` Terraform is free to create the instance before its subnet has a route to the internet gateway. A plan lists what will exist, not the order, so it cannot show this. On LocalStack the bug is invisible because the instance never boots; on real AWS, user_data would run `dnf install httpd` with no route to the internet, the install would fail, and the instance would come up with no web server and no error from Terraform.

### 3. Break only the formatting

Run in CI on the rework pull request; write-up below once the run has finished.

### 4. Turn the bucket off

**What happened:** With `create_bucket = false`, the apply created 9 resources and no bucket. `terraform output bucket_name` did not print null or an empty string: it failed with "Output "bucket_name" not found", and the output was simply missing from `terraform output`, because Terraform does not keep an output whose value is null in the state. Changing `one(aws_s3_bucket.artifacts[*].bucket)` to `aws_s3_bucket.artifacts[0].bucket` made the plan itself fail with "Invalid index".

**Why:** With `count = 0` the bucket is an empty list, so `[0]` asks for an element that does not exist and Terraform refuses to plan, while `[*]` returns an empty list and `one()` turns it into null - a valid value meaning "not created". `one()` lets the same configuration work with the bucket on or off; anything that reads the output has to treat a missing output as "no bucket".

### 5. Point at real AWS on purpose, plan only

**What happened:** With no `-var-file`, `use_localstack` fell back to its default of false and the plan used my LabRole credentials against the real account: 9 resources to add (the VPC, two subnets, the internet gateway, the route table, two associations, the security group and the instance; no bucket, because `create_bucket` defaults to false). The AMI data source resolved a real Amazon Linux 2023 image, `ami-07c1b6f58fb89ce9f` (`al2023-ami-2023.12.20261102.0-kernel-6.12-x86_64`). I did not apply, and afterwards no VPC tagged `Lab=lab5` existed in the account.

**Why:** The workstation always holds live LabRole credentials, so forgetting one flag silently turns a free LocalStack run into billable infrastructure. The one line that would have warned me is in the plan's changes to outputs: `+ provider_target = "aws (REAL account)"`. That is why `provider_target` exists, and why the CI job fails unless it reports `localstack`.
