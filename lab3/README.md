# Lab 3 - Terraform Basics and Your First Pipeline

## Credentials

In a real AWS account the pipeline would use OIDC, where GitHub vouches for each workflow run with a short-lived signed token and AWS exchanges it for temporary access that only works for that one run from this repository, so no long-lived access key is ever stored anywhere where it could be stolen. AWS Academy does not allow students to create the IAM setup that OIDC needs (`iam:CreateOpenIDConnectProvider` and `iam:CreateRole` are denied), so OIDC is described here, not built. This course instead copies the temporary lab-session credentials into GitHub secrets with `refresh-gha-creds.sh`, and the damage from a leak is limited because those credentials stop working when the lab session ends (within about four hours) and can only do what the lab role is allowed to do.

## Terraform version

Terraform **1.16.4** on both the workstation and the pipeline. `main.tf` requires `~> 1.10` (the line that introduced `use_lockfile`), and `lab3-deploy.yml` pins `terraform_version: "1.16.4"` so the workstation and CI never write the shared state with different versions.

## What was built

A push-to-deploy pipeline for one SSM parameter, `acs730-lab3-param`, whose value comes from the Terraform variable `greeting`. The workstation created it first with the value `hello from the workstation`; a pull request then showed the plan, and a merge to `main` made GitHub Actions change the value to `hello from GitHub Actions` - a string that reached AWS without anyone typing it there. Terraform's state is kept in an S3 bucket (`acs730-tfstate-<account-id>`, key `lab3/terraform.tfstate`), so the workstation and the GitHub runners share one record of what exists. When the lab was finished, the parameter was destroyed; only the state bucket remains, because it is used all term.

## Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/create-state-bucket.sh` | S3 bucket `acs730-tfstate-<account-id>` in us-east-1 (account ID looked up with `aws sts get-caller-identity`) if it does not exist; turns on versioning and blocks all public access | Nothing. There is deliberately no delete script: the bucket holds the Terraform state for every lab this term | None | Workstation |
| `scripts/capture-evidence.sh` | Evidence files for the latest push-to-`main` run of `lab3-deploy.yml`: `evidence/apply-run.json` (conclusion, event, branch, commit, URL), `evidence/apply-run-log.txt` (the plan and apply lines from its log) and `evidence/ssm-parameter-after-apply.txt` (a date line and the parameter read back from AWS). Creates no AWS resources | Nothing | None. Needs `gh` signed in; run straight after the merge, before anything else is pushed | Workstation |
| `../scripts/refresh-gha-creds.sh` (repository root, from the course template) | Sets or overwrites the GitHub Actions secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_SESSION_TOKEN`, and the variable `AWS_REGION` (`us-east-1`), after checking the pasted credentials work | Nothing | Required: `<github-owner>/<repo>`. Optional: environment names (e.g. `staging prod`, from Assignment 1) and `--from-file`. Reads the Vocareum "AWS CLI: Show" block from standard input (paste, then Ctrl-D) | Workstation, once per lab session, after Start Lab |

The handout's deliberately broken `check-env.sh` was never added to this repository, so every `.sh` file in `lab3/` parses.

## Terraform and workflows

| File | Creates / changes | Deletes | Triggered by |
|---|---|---|---|
| `main.tf` | Variable `greeting` (default `hello from GitHub Actions` after the change; `hello from the workstation` before it) and SSM parameter `acs730-lab3-param` (String, value `var.greeting`, tags `Name`, `Lab`, `ManagedBy`); outputs the parameter name; pins Terraform `~> 1.10` and the AWS provider `~> 5.0`; S3 backend with `use_lockfile` | The parameter, when `terraform destroy` is run from the workstation at teardown | `terraform plan` / `apply` / `destroy` |
| `.github/workflows/lab3-ci.yml` (repository root) | Nothing - runs `bash -n` on `lab3/scripts/*.sh`, `terraform fmt -check`, `init -backend=false` and `validate`, with no AWS access | Nothing | Pull request, or push to `main`, touching `lab3/**` or the workflow file |
| `.github/workflows/lab3-deploy.yml` (repository root) | On a pull request: a Terraform plan only. On a push to `main`: applies that plan to AWS and updates the state in S3. Pins Terraform 1.16.4. Concurrency group `lab3-terraform` with `cancel-in-progress: false`, so a second run waits and a running apply is never killed | Only what the plan says (nothing was destroyed by the pipeline in this lab) | Pull request or push to `main` touching `lab3/**` or the workflow file, unless the commit message contains `[skip ci]`; manual Run workflow (plan only) |

## How it was proven

1. The workstation applied first and created `acs730-lab3-param` with the value `hello from the workstation`: 1 added (`evidence/workstation-apply.txt`).
2. Pull request #11 pinned the pipeline's Terraform version and switched to the `greeting` variable. Its first plan in GitHub Actions said **No changes** - a different machine reading the same state in S3 and agreeing with it.
3. The next commit on that pull request changed the default to `hello from GitHub Actions`. Both the workstation plan and the pull request plan showed 0 to add, 1 to change, 0 to destroy, with the parameter updated in place.
4. The merge to `main` triggered Actions run [37504147092](https://github.com/jhui26-seneca/acs730-coursework/actions/runs/37504147092) (event `push`, branch `main`, conclusion `success`): **Apply complete! Resources: 0 added, 1 changed, 0 destroyed** (`evidence/apply-run.json`, `evidence/apply-run-log.txt`). Reading the parameter back from AWS returned `hello from GitHub Actions` as version 2 of the same parameter, last modified during that run (`evidence/ssm-parameter-after-apply.txt`).
5. Teardown: `terraform destroy` from the workstation removed the parameter (1 destroyed), and reading it again returned `ParameterNotFound` (`evidence/terraform-destroy.txt`). `cleanup-check.sh` then reported the Lab 3 state empty and nothing left behind except the term-long state bucket. The evidence was merged with `[skip ci]` in the merge commit message, so the pipeline did not run an apply that would have recreated the parameter.

## When a deploy fails

- **ExpiredToken or InvalidClientTokenId:** the lab session the stored credentials came from has ended. Start a new session, re-run `refresh-gha-creds.sh`, then re-run the job. Nothing in the repository changes.
- **403 Forbidden or AccessDenied straight after End Lab, while "Who am I" still passes:** the same cause, seen sooner. Ending the session removes what the credentials are allowed to do before the token itself expires, and `sts get-caller-identity` needs no permission, so it keeps answering. Same fix as above (see Experiment 1).
- **"Input required and not supplied: aws-region":** the `AWS_REGION` variable does not exist - not a credential problem. Run the refresh script, or `gh variable set AWS_REGION --body us-east-1`, and check the workflow reads `vars.AWS_REGION`, not `secrets.AWS_REGION`.

## Evidence

- `evidence/workstation-apply.txt` - the first apply from the workstation: 1 added, value `hello from the workstation`
- `evidence/apply-run.json` - the merged apply run on `main`: conclusion `success`, event `push`, commit and run URL
- `evidence/apply-run-log.txt` - the plan and apply lines from that run: updated in place, 0 added, 1 changed, 0 destroyed
- `evidence/ssm-parameter-after-apply.txt` - a date line, then the parameter read back from AWS: `hello from GitHub Actions`, version 2
- `evidence/terraform-destroy.txt` - the teardown: 1 destroyed, then `ParameterNotFound`

## Other files

- `.terraform.lock.hcl` - records the exact AWS provider version used, so every `terraform init` picks the same one

## Run order

1. Each session: Start Lab, then `../scripts/session-start.sh` and `../scripts/refresh-gha-creds.sh <github-owner>/<repo>`
2. Once: `scripts/create-state-bucket.sh`, then `terraform init` and the first `terraform apply` from the workstation
3. After that, changes go through a pull request (plan) and a merge to `main` (apply); the workstation only runs `terraform plan`
4. Straight after the merge, before anything else is pushed: `scripts/capture-evidence.sh`
5. Teardown: `terraform destroy` from the workstation into `evidence/terraform-destroy.txt`, then `../scripts/cleanup-check.sh`; merge the evidence with `[skip ci]` so the pipeline does not recreate the parameter

## Experiments

For each experiment I made the change, observed the result, and undid the change before moving on to the next one.

### 1. Let the credentials die

**What happened:** After ending the lab session I re-ran the deploy workflow. The "Who am I" step still passed, which surprised me, but the job then failed at Terraform init with a 403 Forbidden when it tried to read the state file from S3, and the validate, plan and apply steps were skipped. Once I started a new session and re-ran the refresh script, the same run went green, and I did not have to change a single file in the repository.

**Why:** Ending the session does not wait for the token to expire; it takes away what the credentials are allowed to do, and an identity check needs no permission at all, so it keeps answering. In my past support work, "authentication works but every real request is denied" was usually a permissions problem, and that is what this looks like from the outside. The practical lesson is that a passing identity check does not prove the credentials are usable, and the fix here is always fresh credentials, never a code change.

### 2. Remove the backend

**What happened:** When I commented out the backend block and re-ran `terraform init -migrate-state`, Terraform unconfigured the S3 backend and copied the state down into a new local file, `terraform.tfstate`, in my `lab3` folder. From that point the only record of the parameter was a file on my workstation that GitHub Actions had no way to see.

**Why:** Had I committed that change, the next CI run would have started on a fresh runner with no state, planned to create the parameter again, and then failed because it already exists in AWS. It is the same problem as two admins each keeping their own copy of a configuration spreadsheet: the moment they diverge, nobody knows which one is true. The shared state in S3 is the single source of truth, and it also keeps the state file, which stores every resource attribute in plain text, out of a public repository.

### 3. Give the apply step a pull request

**What happened:** After changing the apply condition to `if: always()` on a branch and opening a pull request, the pipeline planned and then applied straight from the pull request, using the AWS credentials stored in the repository. Nothing in AWS changed only because the branch matched what was already deployed, and the step still ran even though its name says "push to main only", because the name is just a label.

**Why:** With that condition, anyone who can open a pull request with a branch in my repository could change or destroy real infrastructure before anyone has reviewed it. It is like letting a change request go straight to production while it is still waiting for approval in the change advisory board. The push-to-`main` condition is what separates "propose" from "approve": a pull request can only show a plan, and only a reviewed merge is allowed to touch AWS.

### 4. Race two applies

**What happened:** With `cancel-in-progress: true`, my second push 10 seconds after the first made GitHub cancel the first run, and the second run went on to finish successfully. The first run was marked "cancelled", yet every step in it, including the apply, had already completed, so the status alone told me nothing about whether my infrastructure had changed.

**Why:** Cancelling an outdated test run is safe because tests change nothing and only the newest commit matters, but stopping `terraform apply` halfway through can leave AWS holding resources the state file does not know about. Without the concurrency group, `use_lockfile` would still prevent two applies from writing the state at the same moment, but the second run would fail with "Error acquiring the state lock" instead of queuing behind the first.
