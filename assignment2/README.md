# Assignment 2 - Configuration Management Automation with Ansible and Packer

This folder reaches one end state - an Apache web server serving a known page - two ways. Terraform creates two tagged servers with no SSH access; an Ansible role, found through a dynamic inventory and connected over AWS Systems Manager, configures them, from my workstation and from GitHub Actions straight after `terraform apply`. Packer then bakes the same role into a golden AMI, and both approaches are timed from launch to the first HTTP 200. The graded write-up - introduction, every task, the connection choice, the timings, the comparison and the conclusion - is in **[REPORT.md](REPORT.md)**. This README covers the layout, the files and scripts, and how to run them.

## Layout

| Path | What it is |
|---|---|
| `REPORT.md` | The report |
| `terraform/` | Two web servers, the web security group (HTTP from the VPC only, no port 22) and the Packer security group (no inbound rules) |
| `terraform/timing/` | One timed instance per run, stock or golden, for Task 6 |
| `ansible/` | Configuration, dynamic inventory, group variables, the `webserver` role and two thin plays |
| `packer/` | The golden AMI template |
| `scripts/` | Workstation and CI scripts (table below) |
| `evidence/` | Evidence files (list below) |
| `../.github/workflows/assign2-deploy.yml` | The pipeline: apply, then converge |

## Where it came from

The Terraform target and the two SSM scripts started as copies of my Lab 6 files (`lab6/` is unchanged), then changed for this assignment: `assign2` names, an `Assignment` tag, **two** servers instead of one, their own state key, no IP outputs, and the base image filter pinned to one kernel (`al2023-ami-2023.*-kernel-6.1-x86_64`) so Terraform and Packer always start from the same image. The role is new: generated with `ansible-galaxy role init`, with a second template for Apache settings. The Packer template now runs the role instead of shell commands.

## Terraform (`terraform/main.tf`)

| Creates / changes | Deletes | Notes |
|---|---|---|
| Instances `acs730-assign2-web-1` and `-web-2` (`t3.micro`, tags `Role=web`, `Assignment=assign2`, `LabInstanceProfile`, IMDSv2 only); security groups `acs730-assign2-sg` (port 80 from the default VPC only) and `acs730-assign2-packer-sg` (no inbound rules) | All of the above, through `terraform destroy` (run by `scripts/teardown.sh`) | Default VPC, subnet in us-east-1a. State in `acs730-tfstate-<account>`, key `assign2/terraform.tfstate`. Variable `web_count` (default 2, 1-3). Outputs: instance IDs and the SSM bucket name only. The only `0.0.0.0/0` is outbound. |

## Terraform (`terraform/timing/main.tf`)

| Creates / changes | Deletes | Notes |
|---|---|---|
| One instance `acs730-assign2-b2r-<mode>` in the web security group. `mode=ansible`: stock image, tag `Role=web` (so the role can converge it). `mode=golden`: the newest `acs730-assign2-golden-*` AMI, tag `Role=golden` (kept out of the inventory) | That instance, after timing (by `scripts/boot-to-ready.sh`) | State key `assign2/timing/terraform.tfstate`. Required variable `mode` (`ansible` or `golden`). Launching both through the same configuration gives both timings the same clock start. |

## Ansible (`ansible/`)

| File | Purpose |
|---|---|
| `ansible.cfg` | Points at the dynamic inventory and the roles folder; enables the `amazon.aws.aws_ec2` plugin |
| `inventory/assign2.aws_ec2.yml` | Running instances tagged `Role=web` and `Assignment=assign2`; group `role_web` built from the `Role` tag; hosts named by instance ID. No host list, IDs or IPs |
| `group_vars/role_web.yml` | SSM connection (`community.aws.aws_ssm`), region and transfer bucket, for `role_web` only |
| `site.yml` | Applies the `webserver` role to `role_web` with `become` (workstation and pipeline) |
| `bake.yml` | Applies the same role to `hosts: all` (Packer's one-host inventory) |
| `roles/webserver/` | `ansible-galaxy init` layout. `tasks/main.yml`: install httpd, render the settings and the page, start and enable the service. `defaults/main.yml`: every value used. `handlers/main.yml`: restart, only when the settings change. `templates/index.html.j2` and `templates/acs730-httpd.conf.j2` (`ServerTokens`, `ServerSignature`). `meta/main.yml`, `README.md`, and the generated `vars/`, `files/` and `tests/` |

## Packer (`packer/web.pkr.hcl`)

| Creates | Notes |
|---|---|
| AMI `acs730-assign2-golden-<timestamp>` and its snapshot, tagged (`Assignment`, `ConfiguredBy=ansible-role-webserver`, `SourceAMIName`, ...); a temporary build instance and key pair that Packer removes itself | Plugins `amazon` and `ansible`. Session Manager connection; uses `acs730-assign2-packer-sg`, so no port 22 is ever opened. The Ansible provisioner runs `../ansible/bake.yml` through Packer's tunnel (`use_proxy = false`). No `ami_description`: setting it is a separate `ec2:ModifyImageAttribute` call that the Academy denies. Run from the workstation, not the pipeline. |

## Scripts (`scripts/`)

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `create-ssm-bucket.sh` | S3 bucket `acs730-assign2-ssm-<account>` in us-east-1 with all public access blocked (skips creation if it exists) | Nothing | None | Workstation, once, before the first Ansible run |
| `wait-for-ssm.sh` | Nothing | Nothing | Optional instance IDs; default = every running `Role=web`, `Assignment=assign2` instance | Workstation and the pipeline |
| `boot-to-ready.sh` | One instance through `terraform/timing` and `evidence/boot-to-ready-<mode>.txt` (both clock positions, the timeline and a `RESULT` line; no IP printed) | That instance, after timing | Required: `ansible` or `golden` | Workstation, after the Packer build |
| `teardown.sh` | `evidence/teardown.txt` | Any timing instance, every `acs730-assign2-golden-*` AMI and its snapshots, everything in `terraform/`, and the SSM bucket with its contents; ends with proof that nothing is left | None | Workstation, at the end |
| `../../scripts/refresh-gha-creds.sh` (course template) | The three AWS secrets on each environment named, and the `AWS_REGION` variable | Nothing | Since this assignment: `jhui26-seneca/acs730-coursework staging prod assign2` | Workstation, once per lab session |

## Workflow (`../.github/workflows/assign2-deploy.yml`)

| Event | Job | What it does |
|---|---|---|
| Pull request touching `assignment2/**` | `plan` (environment `assign2`) | Terraform `fmt -check`, `init`, `validate`, `plan`. Changes nothing |
| Push to `main` touching `assignment2/**` (evidence and Markdown excluded), or manual run | `deploy` (environment `assign2`) | Installs pinned Ansible, boto3 and the Session Manager plugin first; then **Terraform apply**; then **Ansible converge** (wait for SSM, inventory graph, `site.yml`); then a second run that fails the job if anything reports `changed` or `failed` |

Runner `ubuntu-24.04`; `shell: bash` so every step runs with `pipefail`; concurrency group `assign2-deploy`, never cancelled mid-apply.

## Evidence

| File | Shows |
|---|---|
| `evidence/caller-identity.png` | The workstation's AWS identity (`assumed-role/LabRole`) |
| `evidence/inventory-graph.txt` | `ansible-inventory --graph`: `@role_web` with both servers, discovered by tag |
| `evidence/role-tree.txt` | The `ansible-galaxy init` layout of `roles/webserver` |
| `evidence/idempotency-run1.txt` | First run: `changed=5` on both servers |
| `evidence/idempotency-run2.txt` | Second run, immediately after: `changed=0 failed=0` on both servers |
| `evidence/template-rendered.txt` | Both rendered files read back off both servers |
| `evidence/pipeline-run.png` | Run 39575896174 (merge of PR #31): green, with **Terraform apply** and **Ansible converge** next to each other |
| `evidence/packer-build.txt` | The timed build: the role on the build instance, the AMI ID, `real 7m6.8s` |
| `evidence/ami-describe.json` | `ami-09aa9cd6223cb2891`: name, tags, creation date, snapshot |
| `evidence/golden-ami.png` | The AMI in the console, with its snapshot on the Storage tab |
| `evidence/boot-to-ready-ansible.txt` | 92 s from `terraform apply` to the first HTTP 200, with both clock positions |
| `evidence/boot-to-ready-golden.txt` | 30 s, same clock positions |
| `evidence/teardown.txt` | AMI deregistered, snapshot deleted, `4 destroyed`, bucket deleted, every proof list empty |

## Run order

1. Each session: Start Lab, `source ~/acs730-assign2-venv/bin/activate`, `../scripts/session-start.sh`, then `../scripts/refresh-gha-creds.sh jhui26-seneca/acs730-coursework staging prod assign2`.
2. `terraform -chdir=terraform init && terraform -chdir=terraform apply`, then `scripts/create-ssm-bucket.sh` and `scripts/wait-for-ssm.sh`.
3. From `ansible/`: `ansible-inventory --graph`, then `ansible-playbook site.yml` twice.
4. Open a pull request (plan), merge it (apply, then converge in the pipeline).
5. From `packer/`: `packer init`, `packer validate`, `packer build web.pkr.hcl`.
6. `scripts/boot-to-ready.sh ansible`, then `scripts/boot-to-ready.sh golden`.
7. `scripts/teardown.sh`, then `../scripts/cleanup-check.sh`. Merge evidence and documentation with `[skip ci]` in the merge subject.
