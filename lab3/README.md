# Lab 3 - Terraform Basics and Your First Pipeline

## Credentials

In a real AWS account the pipeline would use OIDC, where GitHub vouches for each workflow run with a short-lived signed token and AWS exchanges it for temporary access that only works for that one run from this repository, so no long-lived access key is ever stored anywhere where it could be stolen. AWS Academy does not allow students to create the IAM setup that OIDC needs, so this course instead copies the temporary lab-session credentials into GitHub secrets, and the damage from a leak is limited because those credentials stop working when the lab session ends (within about four hours) and can only do what the lab role is allowed to do.

## What was built

A push-to-deploy pipeline: Terraform (`main.tf`) describes one security group, `acs730-lab3-sg`. A pull request shows the Terraform plan, and a merge to `main` makes GitHub Actions apply it automatically. Terraform's state is kept in an S3 bucket (`acs730-tfstate-<account-id>`, key `lab3/terraform.tfstate`), so the workstation and the GitHub runners share one record of what exists.

## Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/create-state-bucket.sh` | S3 bucket `acs730-tfstate-<account-id>` in us-east-1 (account ID looked up with `aws sts get-caller-identity`) if it does not exist; turns on versioning and blocks all public access | Nothing. There is deliberately no delete script: the bucket holds the Terraform state for every lab this term | None | Workstation |
| `scripts/capture-evidence.sh` | The evidence file `evidence/deploy-run.txt` (overwritten each run): URL, title, trigger, commit and result of the latest successful `lab3-deploy.yml` run on a push to `main`, its plan and apply lines, and a table of every `acs730-lab3-sg` in AWS. Creates no AWS resources | Nothing | None. Needs `gh` signed in and must be run inside the repository | Workstation |
| `../scripts/refresh-gha-creds.sh` (repository root, from the course template) | Sets or overwrites the GitHub Actions secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`, and the variable `AWS_REGION` (`us-east-1`), after checking the pasted credentials work | Nothing | Required: `<github-owner>/<repo>`. Optional: environment names (e.g. `staging prod`, from Assignment 1) and `--from-file`. Reads the Vocareum "AWS CLI: Show" block from standard input (paste, then Ctrl-D) | Workstation, once per lab session, after Start Lab |

## Terraform and workflows

| File | Creates / changes | Deletes | Triggered by |
|---|---|---|---|
| `main.tf` | Security group `acs730-lab3-sg` (tags `Name`, `Lab`, `ManagedBy`, `Revision`); pins Terraform `~> 1.10` and the AWS provider `~> 5.0`; S3 backend with `use_lockfile` | Nothing (no destroy is run) | `terraform plan` / `apply` |
| `.github/workflows/lab3-ci.yml` (repository root) | Nothing - runs `bash -n` on `lab3/scripts/*.sh`, `terraform fmt -check`, `init -backend=false` and `validate`, with no AWS access | Nothing | Pull request, or push to `main`, touching `lab3/**` or the workflow file |
| `.github/workflows/lab3-deploy.yml` (repository root) | On a pull request: a Terraform plan only. On a push to `main`: applies that plan to AWS and updates the state in S3. Concurrency group `lab3-terraform` stops two runs applying at once | Only what the plan says (none in this lab) | Pull request or push to `main` touching `lab3/**` or the workflow file; manual Run workflow (plan only) |

## How it was proven

1. The workstation applied first and created security group `sg-0b097709c323bb8be` with tag `Revision = 1` (`evidence/workstation-apply.txt`).
2. Pull request #3 added the workflows; on merge, GitHub Actions read the same state and reported 0 added, 0 changed, 0 destroyed.
3. Pull request #4 changed the tag to `Revision = 2`. The pull request plan showed 0 to add, 1 to change, 0 to destroy, and the merge to `main` triggered an automatic apply in Actions run [36363185258](https://github.com/jhui26-seneca/acs730-coursework/actions/runs/36363185258): 0 added, 1 changed, 0 destroyed. The same security group `sg-0b097709c323bb8be` was updated in place, not duplicated (`evidence/deploy-run.txt`).

## Other files

- `.terraform.lock.hcl` - records the exact AWS provider version used, so every `terraform init` picks the same one
- `evidence/workstation-apply.txt` - the first apply from the workstation
- `evidence/deploy-run.txt` - the automatic apply triggered by the merge to `main`

## Run order

1. Each session: Start Lab, then `../scripts/refresh-gha-creds.sh <github-owner>/<repo>`
2. Once: `scripts/create-state-bucket.sh`, then `terraform init` and the first `terraform apply` from the workstation
3. After that, changes go through a pull request (plan) and a merge to `main` (apply); the workstation only runs `terraform plan`
4. After the merge: `scripts/capture-evidence.sh`
