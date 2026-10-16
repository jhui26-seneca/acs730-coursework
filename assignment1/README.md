# Assignment 1 - Multi-Environment Infrastructure Deployment with Terraform

This folder turns the network and web server I built in Lab 5 into one reusable Terraform module, `web-env`, and calls it once per environment with that environment's own values. dev is built from my workstation by script; staging and prod are added and deployed by the GitHub Actions pipeline in the next pull request. The graded write-up (introduction, tasks, the OIDC trust policy, the recommendation and the conclusion) goes in `REPORT.md`; this README covers the layout, the files and scripts, and how to run them.

## Layout

| Path | What it is |
|---|---|
| `terraform/modules/web-env/` | The module: VPC, two public subnets, internet gateway, route table, an HTTP-only security group, the web server, its CloudWatch CPU alarm, and the SSM data source that reads the database password |
| `terraform/dev/` | The dev caller: its own S3 state key, created and destroyed from my workstation by script - the pipeline never deploys dev |
| `terraform/ci-localstack/` | The same module applied and destroyed against LocalStack on every pull request, with no AWS credentials |
| `scripts/` | Workstation scripts (table below) |
| `evidence/` | Evidence files (list below) |

## Where the module came from

I copied `versions.tf`, `variables.tf`, `network.tf`, `compute.tf` and `outputs.tf` from `lab5/` (which stays exactly as I submitted it) and changed the copies:

- Every name is `acs730-assign1-<environment>-<type>`, so two environments can never collide in the same account.
- The S3 bucket is gone: the Academy account denies a read the Terraform AWS provider makes after creating any bucket, which I ran into in Lab 6. Port 443 is gone too, because nothing listens on it.
- The web server now has `LabInstanceProfile` and IMDSv2 only, so Session Manager is the way in. There is no port 22 anywhere, and the `ingress_rules` variable refuses port 22 with a validation error.
- New files: `secrets.tf` (the SSM data source) and `monitoring.tf` (the CPU alarm).
- The provider, the default tags and the backend moved out of the module into each caller, because a module should not decide where it deploys or where its state lives.

## Module inputs

| Input | Type | What it controls | dev value |
|---|---|---|---|
| `environment` | string, validated | Name used in every resource name: `ci`, `dev`, `staging` or `prod` | `dev` |
| `vpc_cidr` | string, validated | The environment's VPC range; the two /24 subnets are carved from it | `10.10.0.0/16` |
| `instance_type` | string, validated (`t3.micro` or `t3.small`) | Web server size | `t3.micro` |
| `ingress_rules` | list of objects, validated (no port 22) | Security group inbound rules | default: HTTP 80 from anywhere |
| `ami_name_filter`, `ami_owners` | string, list | Which image the web server uses | default: standard Amazon Linux 2023 |
| `instance_profile_name` | string | Instance profile for the SSM agent | default: `LabInstanceProfile` |
| `detailed_monitoring` | bool | 60-second EC2 metrics instead of 300-second; also sets the alarm period | `false` |
| `cpu_alarm_threshold` | number, validated (1-100) | CPU % that puts the alarm into ALARM | `80` |
| `alarm_evaluation_periods` | number, validated (1-10) | Periods that must breach before it fires | default: `3` |
| `db_password_parameter_name` | string, validated (`/acs730/assign1/...`) | The SSM parameter the data source reads | `/acs730/assign1/dev/db_password` |

Outputs: `environment`, `vpc_id`, `subnet_ids`, `security_group_id`, `instance_id`, `web_public_ip`, `web_url`, `cpu_alarm_name`, `db_password_parameter_name`, `db_password_parameter_version`, and `db_password` (marked sensitive).

## The database password (Task 6)

The password is a placeholder, created once per environment by `scripts/create-ssm-parameters.sh` as a SecureString with `aws ssm put-parameter`. Terraform only reads it, through `data "aws_ssm_parameter"` in `secrets.tf`; nothing in Terraform creates it, because creating and reading the same parameter in one graph fails on a fresh environment. The web server's user_data writes the value into `/etc/acs730/app.env` (owner root, mode 0600) for the application, and the web page only shows which parameter and version were loaded. Because the value is sensitive, Terraform hides the whole user_data in every plan and pipeline log.

## The alarm (Task 7)

`aws_cloudwatch_metric_alarm` watches the web server's `CPUUtilization` in `AWS/EC2`. Its period follows `detailed_monitoring` (60 s or 300 s), because an alarm with a shorter period than the metric never gets a datapoint. Missing data is treated as missing, so the alarm shows `INSUFFICIENT_DATA` until real datapoints arrive instead of pretending to be `OK`.

## GitHub Environments (Task 3)

| Environment | Reviewer | Deployment branches |
|---|---|---|
| `staging` | none - a merge to `main` deploys it automatically | any |
| `prod` | `jhui26-seneca` required; self-review allowed because I am the only person on the repository | `main` only |

Both were created with `scripts/configure-environments.sh`; `evidence/environments.json` is the API's own record of them.

## Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/configure-environments.sh` | GitHub Environments `staging` (no reviewer) and `prod` (required reviewer, self-review allowed, deployment branch policy `main`); updates them if they exist | Nothing | `<owner>/<repo>` | Workstation (needs `gh` signed in) |
| `scripts/capture-evidence.sh` | `evidence/environments.json` (both environments plus prod's branch policies, as one JSON document) | Nothing | `<owner>/<repo> environments` | Workstation |
| `scripts/create-ssm-parameters.sh` | SecureString `/acs730/assign1/<env>/db_password` with a placeholder value, for each environment named; leaves an existing one unchanged | Nothing | One or more of `dev`, `staging`, `prod` | Workstation |
| `scripts/delete-ssm-parameters.sh` | Nothing | `/acs730/assign1/<env>/db_password` for each environment named | One or more of `dev`, `staging`, `prod` | Workstation, after `destroy-env.sh` |
| `scripts/create-dev.sh` | The dev parameter (via `create-ssm-parameters.sh dev`), then everything in the module for dev: VPC `acs730-assign1-dev-vpc`, subnets `-subnet-a`/`-b`, `-igw`, `-rt` and its associations, `-sg`, instance `-web`, alarm `-cpu-alarm`; waits for the page; writes `evidence/dev-apply.txt`. Stops without applying if the plan would destroy anything | Nothing | None | Workstation |
| `scripts/destroy-env.sh` | Nothing | Everything Terraform built for that environment (`terraform destroy`) | `dev`, `staging` or `prod` | Workstation |

## Terraform and workflows

| File | Creates / changes | Triggered by |
|---|---|---|
| `terraform/modules/web-env/*.tf` | The resources listed above, for whichever environment calls it | A caller's `terraform apply` |
| `terraform/dev/*.tf` | dev, with state key `assign1/dev/terraform.tfstate` in `acs730-tfstate-<account-id>` | `scripts/create-dev.sh` |
| `terraform/ci-localstack/*.tf` | The module's resources inside LocalStack only; no backend, so its state never touches the real bucket | `assign1-ci.yml` |
| `../.github/workflows/assign1-ci.yml` | Nothing in AWS. Job `gates`: `bash -n` on the scripts, `terraform fmt -check`, and `init -backend=false` + `validate` for the module and every caller. Job `localstack` (needs `gates`): seeds LocalStack with `LabInstanceProfile` and a placeholder parameter, then plan, apply, an account-ID guard (must be `000000000000`) and destroy | Pull request, or push to `main`, touching `assignment1/**` or the workflow |

## Evidence

- `evidence/caller-identity.png` - my workstation's AWS identity (assumed-role/LabRole)
- `evidence/environments.json` - staging with no reviewer, prod with a required reviewer and the `main` branch policy
- `evidence/dev-apply.txt` - dev built by `create-dev.sh`: the plan, the apply and the page it serves

## Run order so far

1. Each session: Start Lab, then `../scripts/session-start.sh`.
2. Once: `scripts/configure-environments.sh <owner>/<repo>`, then `scripts/capture-evidence.sh <owner>/<repo> environments`.
3. dev: `scripts/create-dev.sh`; teardown: `scripts/destroy-env.sh dev`, then `scripts/delete-ssm-parameters.sh dev`.
