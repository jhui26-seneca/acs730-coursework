# Lab 6 - Ansible Configuration Management and Golden AMIs

Terraform creates a tagged target in the default VPC with LabInstanceProfile and no port 22 ingress at all. Ansible finds it by tag and configures it over AWS Systems Manager, from the workstation and from GitHub Actions. Packer bakes the same web page into a golden AMI, and both approaches are timed from launch to the page being served.

## The three answers

I used Ansible over SSM (the community.aws.aws_ssm connection), because the instance's SSM agent connects outbound using LabInstanceProfile, so neither the workstation nor the GitHub runner needs an SSH key and port 22 is never opened, which removes both the stored-key and the open-port security findings. A second run reporting changed=0 proves the role describes a desired state rather than a list of actions: every task checked the server, found it already correct and changed nothing, so the playbook is safe to run repeatedly in a pipeline and will correct drift. Deregistering an AMI only deletes the image record; the EBS snapshot holding its disk stays behind and keeps billing, so teardown must delete the snapshot as well.

## Boot-to-ready

| Approach | Launch request to page served |
|---|---|
| Plain Amazon Linux 2023 + Ansible over SSM | <N> s (evidence/boot-to-ready-ansible.txt) |
| Golden AMI baked by Packer | <N> s (evidence/boot-to-ready-golden.txt) |

The golden AMI is faster and has nothing left to fail at launch, but it is only as current as its last build; the Ansible path is slower and depends on SSM and the package mirror at boot, but every run applies the latest playbook.

## Terraform (terraform/main.tf)

| Creates / changes | Deletes | Notes |
|---|---|---|
| Instance `acs730-lab6-web` (tags Role=web, Lab=lab6; LabInstanceProfile; IMDSv2), security groups `acs730-lab6-sg` (port 80 from the VPC only) and `acs730-lab6-packer-sg` (no ingress) | Everything above, via `terraform destroy` (run by scripts/teardown.sh) | Default VPC, subnet in us-east-1a; state in `acs730-tfstate-<account>`, key `lab6/terraform.tfstate`. The SSM bucket is not in Terraform: the Academy account's service control policy denies `s3:GetBucketObjectLockConfiguration`, which the AWS provider reads after creating any bucket, so the bucket is created by `scripts/create-ssm-bucket.sh` instead. |

## Ansible (ansible/)

| File | Purpose |
|---|---|
| `ansible.cfg` | Points at the dynamic inventory and the roles folder |
| `inventory/lab6.aws_ec2.yml` | amazon.aws.aws_ec2 plugin; running instances tagged Role=web and Lab=lab6; keyed_groups builds group `role_web`; no IDs or IPs in the file |
| `group_vars/role_web.yml` | SSM connection, bucket and region (both us-east-1) |
| `site.yml` | Applies the `webserver` role to `role_web` with become |
| `roles/webserver/` | tasks (dnf, template, service), defaults, a restart handler, and `templates/index.html.j2` with no timestamps |

## Packer (packer/)

| File | Creates | Notes |
|---|---|---|
| `web.pkr.hcl` | AMI `acs730-lab6-golden-<timestamp>` and its snapshot; a temporary build instance and key pair that Packer removes itself | Connects through Session Manager; uses `acs730-lab6-packer-sg` so no port-22 group is ever created |
| `files/index.html` | Nothing (the page baked into the image) | |

## Scripts (scripts/)

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `create-ssm-bucket.sh` | S3 bucket `acs730-lab6-ssm-<account>` in us-east-1 with all public access blocked (skips creation if it exists) | Nothing | None | Workstation, once, before the first Ansible run |
| `wait-for-ssm.sh` | Nothing | Nothing | Optional instance ID; default = every running Role=web, Lab=lab6 instance | Workstation and CI |
| `boot-to-ready.sh` | One t3.micro `acs730-lab6-b2r-<mode>` and `evidence/boot-to-ready-<mode>.txt` | That instance, when timing ends | Required: `ansible` or `golden` | Workstation |
| `teardown.sh` | `evidence/teardown.txt` | Leftover timing instances, every `acs730-lab6-golden-*` AMI and its snapshots, everything Terraform created, and the SSM bucket with its contents | None | Workstation |

## Workflow (.github/workflows/lab6-configure.yml)

| Event | What it does |
|---|---|
| Pull request touching lab6/** | Terraform fmt, validate and plan |
| Push to main (or manual run) | Terraform apply, install Ansible + boto3 + session-manager-plugin, wait for SSM Online, inventory graph, converge, then a second run that fails the job if anything reports changed |

## Evidence

- `caller-identity.png` - workstation identity at the start
- `inventory-graph.txt` - the tag-built `role_web` group
- `idempotency-run1.txt`, `idempotency-run2.txt` - the second run reports changed=0
- `pipeline-run.png` - the merge-triggered pipeline, green
- `packer-build.txt`, `golden-ami.png` - the bake and the resulting AMI
- `boot-to-ready-ansible.txt`, `boot-to-ready-golden.txt` - the timings
- `teardown.txt` - everything removed, including the snapshot and the SSM bucket
