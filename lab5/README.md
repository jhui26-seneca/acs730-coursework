# Lab 5 - Terraform Introduction and Reliable CI

One Terraform configuration describes a complete public network and a web server. The `use_localstack` variable decides whether it targets real AWS or LocalStack, a local AWS emulator. Every pull request validates it against LocalStack in CI, with no AWS credentials in the pipeline.

## Design note: why not real AWS on every pull request

Running `terraform plan` and `apply` against real AWS on every pull request is slow, because a VPC, a gateway and an instance take minutes to create and destroy where LocalStack takes seconds. It is expensive, because every run creates billable resources, and a forgotten teardown or a NAT gateway keeps charging whether it is used or not. It is flaky, because the result depends on the cloud account, its quotas and its credentials, not just on the change being reviewed.

In an AWS Academy account all three get worse. The credentials expire when the lab session ends, so a check that ran green at noon fails with ExpiredToken in the evening for reasons unrelated to the code. There is a fixed $50 credit shared with every other lab, and IAM is locked down. A required check that depends on all of that would block merges at random. LocalStack gives a fast, free and repeatable answer to the question CI should ask, "is this configuration coherent?", while the real deploy happens deliberately, later. A green LocalStack run does not prove the deploy will work: LocalStack does not enforce IAM and never boots user_data.

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
