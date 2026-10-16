# Assignment 1 - Multi-Environment Infrastructure Deployment with Terraform

This folder turns the network and web server I built in Lab 5 into one reusable Terraform module, `web-env`, and calls it three times - dev, staging and prod - with each environment's own values and its own state. dev is built from my workstation by script; staging is deployed by GitHub Actions on every merge to `main`; prod is deployed by the same pipeline only after I approve it as the required reviewer. The graded write-up - introduction, every task, the OIDC trust policy, the Task 8 recommendation and the conclusion - is in **[REPORT.md](REPORT.md)**. This README covers the layout, the files and scripts, and how to run them.

## Layout

| Path | What it is |
|---|---|
| `REPORT.md` | The report |
| `terraform/modules/web-env/` | The module: VPC, two public subnets, internet gateway, route table, an HTTP-only security group, the web server, its CloudWatch CPU alarm, and the SSM data source that reads the database password |
| `terraform/dev/`, `staging/`, `prod/` | The three callers: same module, different values, each with its own S3 state key |
| `terraform/ci-localstack/` | The same module applied and destroyed against LocalStack on every pull request, with no AWS credentials |
| `scripts/` | Workstation scripts (table below) |
| `evidence/` | Evidence files (list below) |

## Where the module came from

I copied `versions.tf`, `variables.tf`, `network.tf`, `compute.tf` and `outputs.tf` from `lab5/` (which stays exactly as I submitted it) and changed the copies:

- Every name is `acs730-assign1-<environment>-<type>`, so environments can never collide in the same account.
- The S3 bucket is gone: the Academy account denies a read the Terraform AWS provider makes after creating any bucket, which I ran into in Lab 6. Port 443 is gone too, because nothing listens on it.
- The web server has `LabInstanceProfile` and IMDSv2 only, so Session Manager is the way in. There is no port 22 anywhere, and the `ingress_rules` variable refuses port 22 with a validation error.
- New files: `secrets.tf` (the SSM data source) and `monitoring.tf` (the CPU alarm).
- The provider, the default tags and the backend moved out of the module into each caller, because a module should not decide where it deploys or where its state lives.

## The environments

| | dev | staging | prod |
|---|---|---|---|
| State key in `acs730-tfstate-<account-id>` | `assign1/dev/terraform.tfstate` | `assign1/staging/terraform.tfstate` | `assign1/prod/terraform.tfstate` |
| `vpc_cidr` | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` |
| `instance_type` | `t3.micro` | `t3.micro` | `t3.micro` |
| `detailed_monitoring` (alarm period) | `false` (300 s) | `true` (60 s) | `true` (60 s) |
| `cpu_alarm_threshold` | 80 | 70 | 60 |
| SSM parameter | `/acs730/assign1/dev/db_password` | `/acs730/assign1/staging/db_password` | `/acs730/assign1/prod/db_password` |
| Deployed by | `scripts/create-dev.sh` (workstation) | `assign1-deploy.yml`, automatically on merge | `assign1-deploy.yml`, after a required reviewer approves |
| GitHub Environment | none | `staging`: no reviewer | `prod`: reviewer `jhui26-seneca`, `main` only |

## Module inputs and outputs

| Input | Type | What it controls |
|---|---|---|
| `environment` | string, validated (`ci`, `dev`, `staging`, `prod`) | Every resource name and the page heading |
| `vpc_cidr` | string, validated, no default | The VPC range; the two /24 subnets are carved from it |
| `instance_type` | string, validated (`t3.micro` or `t3.small`) | Web server size |
| `ingress_rules` | list of objects, validated (no port 22) | Security group inbound rules; default HTTP 80 from anywhere |
| `ami_name_filter`, `ami_owners` | string, list | The image; default standard Amazon Linux 2023 (it has the SSM agent) |
| `instance_profile_name` | string | Default `LabInstanceProfile`, for Session Manager |
| `detailed_monitoring` | bool | 60-second EC2 metrics instead of 300-second; also sets the alarm period |
| `cpu_alarm_threshold` | number, validated (1-100), no default | CPU % that puts the alarm into ALARM |
| `alarm_evaluation_periods` | number, validated (1-10) | Periods that must breach; default 3 |
| `db_password_parameter_name` | string, validated (`/acs730/assign1/...`) | The SSM parameter the data source reads |

Outputs: `environment`, `vpc_id`, `subnet_ids`, `security_group_id`, `instance_id`, `web_public_ip`, `web_url`, `cpu_alarm_name`, `db_password_parameter_name`, `db_password_parameter_version`, and `db_password` (marked sensitive).

## Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/configure-environments.sh` | GitHub Environments `staging` (no reviewer) and `prod` (required reviewer, self-review allowed, deployment branch policy `main`); updates them if they exist | Nothing | `<owner>/<repo>` | Workstation (needs `gh` signed in) |
| `scripts/create-ssm-parameters.sh` | SecureString `/acs730/assign1/<env>/db_password` with a placeholder value for each environment named - the out-of-band pre-step for Task 6; leaves an existing one unchanged | Nothing | One or more of `dev`, `staging`, `prod` | Workstation, before the first plan of that environment |
| `scripts/create-dev.sh` | The dev parameter (via `create-ssm-parameters.sh dev`), then everything in the module for dev (VPC `acs730-assign1-dev-vpc`, subnets `-subnet-a`/`-b`, `-igw`, `-rt` and associations, `-sg`, instance `-web`, alarm `-cpu-alarm`); waits for the page; writes `evidence/dev-apply.txt`. Stops without applying if the plan would destroy anything | Nothing | None | Workstation |
| `scripts/delete-repo-secrets.sh` | Nothing | The repository-level `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`; refuses to run unless both environments already hold all three | `<owner>/<repo>` | Workstation, after `../scripts/refresh-gha-creds.sh <owner>/<repo> staging prod` |
| `scripts/capture-evidence.sh` | One evidence file per item: `environments.json`, `secrets-scope.txt`, `staging-apply.txt`, `prod-apply.txt`, `backend-state-keys.txt`, `ssm-parameter.txt`, `cloudwatch-alarm.json` (waits until the alarm leaves `INSUFFICIENT_DATA`). Creates no AWS resources | Nothing | `<owner>/<repo> <item>`, plus the run ID for `staging-apply` and `prod-apply`, or an environment (default `prod`) for `ssm-parameter` and `cloudwatch-alarm` | Workstation |
| `scripts/destroy-env.sh` | Nothing | Everything Terraform built for that environment (`terraform destroy`) | `dev`, `staging` or `prod` | Workstation |
| `scripts/delete-ssm-parameters.sh` | Nothing | `/acs730/assign1/<env>/db_password` for each environment named (no destroy removes them, because Terraform never created them) | One or more of `dev`, `staging`, `prod` | Workstation, after `destroy-env.sh` |
| `scripts/teardown.sh` | `evidence/destroy-complete.txt` | dev, staging and prod (via `destroy-env.sh`), then all three SSM parameters; ends with proof that nothing is left | None | Workstation |
| `../scripts/refresh-gha-creds.sh` (course template) | The three AWS secrets on each environment named, and the `AWS_REGION` variable | Nothing | Since Task 4: `jhui26-seneca/acs730-coursework staging prod` | Workstation, once per lab session |

## Workflows

| File | Creates / changes | Triggered by |
|---|---|---|
| `../.github/workflows/assign1-ci.yml` | Nothing in AWS. Job `gates`: `bash -n` on the scripts, `terraform fmt -check`, and `init -backend=false` + `validate` for the module and every caller. Job `localstack` (needs `gates`): seeds LocalStack with `LabInstanceProfile` and a placeholder parameter, then plan, apply, an account-ID guard (must be `000000000000`) and destroy | Pull request, or push to `main`, touching `assignment1/**` |
| `../.github/workflows/assign1-deploy.yml` | Job `staging` (environment `staging`): init, plan, apply, smoke test of the page. Job `prod` (environment `prod`, `needs: staging`): waits for the required reviewer, then the same steps. Each job reads only its own environment's secrets; concurrency group `assign1-deploy`, never cancelled mid-apply | Push to `main` touching `assignment1/**` except `evidence/` and Markdown; manual run |

## How it was proven

1. **PR #25** - module, dev, LocalStack check and GitHub Environments. dev was built by `create-dev.sh` (10 resources), checked (page, SSM value, HTTP-only security group, Session Manager `Online`, `/etc/acs730/app.env` root-only) and destroyed. LocalStack showed one limit of emulation: it does not implement EC2 `MonitorInstances`, so the LocalStack caller runs without detailed monitoring.
2. **Task 4** - credentials written to `staging` and `prod`, repository copies deleted, `secrets-scope.txt` captured; all before the deploy workflow was merged, so the deployment could only use environment secrets.
3. **PR #26, run 38853932149** - staging applied itself on the merge (10 added, smoke test passed). After I approved prod, the AWS Academy's management role (`assumed-role/vocareum/resource`, per CloudTrail) stopped every instance in the account at 05:14 UTC while prod was deploying.
4. **PR #27, run 38857506268** - recovery: dev left stopped, the half-built prod destroyed, staging restarted, prod set to `t3.micro`, and merged again. Staging changed nothing; prod waited at the gate from 05:46:39 until my approval at 05:51:09, then applied 10 resources and passed its smoke test. The alarm reached `OK` at 05:54:42 UTC.
5. **Teardown** - `teardown.sh` destroyed all three environments (10 resources each) and the three parameters; `cleanup-check.sh` found nothing left.

## Evidence

| File | Shows |
|---|---|
| `evidence/caller-identity.png` | The workstation's AWS identity (`assumed-role/LabRole`) |
| `evidence/environments.json` | `staging` with no rules; `prod` with required reviewer `jhui26-seneca` and the deployment branch policy `main` |
| `evidence/secrets-scope.txt` | No AWS secret at repository level; all three on `staging` and on `prod` |
| `evidence/dev-apply.txt` | dev built by `create-dev.sh`: plan, apply and the page |
| `evidence/staging-apply.txt` | Run 38853932149 (merge of PR #26): the staging job started 3 seconds after it was created, no approval, `Apply complete! Resources: 10 added`, page answered |
| `evidence/prod-approval-pending.png` | Run 38857506268 waiting: "requested your review to deploy to prod", staging already green |
| `evidence/prod-approval-approved.png` | The same run after approval: approved by `jhui26-seneca` with the comment, prod deploying |
| `evidence/prod-apply.txt` | The approval and deployment history first (`waiting` 05:46:40, `queued` 05:51:09, `success` 05:52:50), then the prod job log: `Plan: 10 to add`, `Apply complete! Resources: 10 added`, page answered |
| `evidence/backend-state-keys.txt` | Three state objects in the bucket: `assign1/dev`, `assign1/staging`, `assign1/prod` |
| `evidence/ssm-parameter.txt` | The prod parameter in AWS and the value Terraform's data source read, side by side |
| `evidence/cloudwatch-alarm.json`, `evidence/cloudwatch-alarm.png` | The prod CPU alarm: `AWS/EC2` `CPUUtilization`, Average > 60, 60 s x 3, state `OK`, with the graph and threshold line |
| `evidence/destroy-complete.txt` | `Destroy complete!` for dev, staging and prod, the parameters deleted, and empty lists proving nothing is left |

## Run order

1. Each session: Start Lab, then `../scripts/session-start.sh` and `../scripts/refresh-gha-creds.sh jhui26-seneca/acs730-coursework staging prod`.
2. Once: `scripts/configure-environments.sh jhui26-seneca/acs730-coursework`.
3. Parameters: `scripts/create-ssm-parameters.sh dev staging prod`.
4. dev: `scripts/create-dev.sh`.
5. staging and prod: open a pull request (LocalStack check), merge it (staging deploys), read the prod plan, approve the `prod` deployment in the Actions run.
6. Teardown: `scripts/teardown.sh`, then `../scripts/cleanup-check.sh`. Merge evidence and documentation with `[skip ci]` in the merge subject.
