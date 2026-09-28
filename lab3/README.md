# Lab 3 - Terraform Basics and Your First Pipeline

## Credentials

In a real AWS account the pipeline would use OIDC, where GitHub vouches for
each workflow run with a short-lived signed token and AWS exchanges it for
temporary access that only works for that one run from this repository, so no
long-lived access key is ever stored anywhere where it could be stolen. AWS
Academy does not allow students to create the IAM setup that OIDC needs, so
this course instead copies the temporary lab-session credentials into GitHub
secrets, and the damage from a leak is limited because those credentials stop
working when the lab session ends (within about four hours) and can only do
what the lab role is allowed to do.

## What was built

A push-to-deploy pipeline: Terraform describes one security group
(acs730-lab3-sg), a pull request shows the Terraform plan, and a merge to
main makes GitHub Actions apply it automatically. Terraform's state is kept
in an S3 bucket (acs730-tfstate-<account-id>, key lab3/terraform.tfstate)
so the workstation and the GitHub runners share one record of what exists.

## How it was proven

1. The workstation applied first and created security group
   sg-0b097709c323bb8be with tag Revision = 1 (evidence/workstation-apply.txt).
2. Pull request #3 added the workflows; on merge, GitHub Actions read the same
   state and reported 0 added, 0 changed, 0 destroyed.
3. Pull request #4 changed the tag to Revision = 2. The pull request showed
   "Plan: 0 to add, 1 to change, 0 to destroy", and the merge to main
   triggered an automatic apply in Actions run 36363185258:
   https://github.com/jhui26-seneca/acs730-coursework/actions/runs/36363185258
   Result: 0 added, 1 changed, 0 destroyed - the same security group
   sg-0b097709c323bb8be was updated in place, not duplicated
   (evidence/deploy-run.txt).

## Files

- main.tf - one security group; Terraform (~> 1.10) and AWS provider
  (~> 5.0) versions pinned; S3 backend with use_lockfile
- .terraform.lock.hcl - records the exact provider version used
- scripts/create-state-bucket.sh - creates the S3 state bucket (kept for the
  whole term, so there is no delete script)
- scripts/capture-evidence.sh - records the latest successful apply on main
  and confirms only one acs730-lab3-sg exists in AWS
- evidence/workstation-apply.txt - first apply from the workstation
- evidence/deploy-run.txt - automatic apply triggered by the merge to main
- Workflows (at the repository root):
  .github/workflows/lab3-ci.yml - checks scripts and Terraform, no AWS access
  .github/workflows/lab3-deploy.yml - plan on pull request, apply only on
  push to main, with a concurrency group so two runs cannot apply at once
