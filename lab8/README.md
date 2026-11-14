# Lab 8: Security and policy as code

`lab8/main.tf` describes a small web host in the default VPC: one security group, its two rules and one t3.micro instance. It is only ever planned and scanned, never applied. `tfsec lab8 --minimum-severity HIGH` exits 0 on it, and that scan is a required check on `main`.

## The finding I reproduced

The first version of `main.tf` (commit `29c5931`, replaced before the merge) opened SSH to the whole internet: `cidr_blocks = ["0.0.0.0/0"]` on port 22. tfsec reported it as `aws-ec2-no-public-ingress-sgr`, CRITICAL, at `main.tf:57`, with the resolution "Set a more restrictive cidr range". The same file also left the root volume unencrypted (`aws-ec2-enable-at-rest-encryption`, HIGH) and allowed IMDSv1 (`aws-ec2-enforce-http-token-imds`, HIGH). An open port 22 is found by internet-wide scanners within minutes of an instance starting. From there an attacker can brute-force or reuse passwords and keys, or exploit an unpatched `sshd`, to get a shell. With IMDSv1 that shell, or even a server-side request forgery bug in the web app, can read the instance role's temporary credentials from `169.254.169.254` with a single unauthenticated GET. An unencrypted volume means any snapshot or copy of the disk can be read by whoever gets hold of it. The fixed file allows SSH only from one `/32` (`var.admin_cidr`, with a validation rule that refuses anything else; the default is the documentation address `203.0.113.10/32`, because this repository is public and my own IP doesn't belong in it), sets `encrypted = true` and requires IMDSv2.

## Why the scan blocks a merge

`.github/workflows/lab8-policy.yml` runs one job, `tfsec (HIGH and above)`, on every pull request and every push to `main`. Its gate step is `tfsec lab8 --minimum-severity HIGH --no-color`, with no `|| true`, no `continue-on-error` and no `soft_fail`, and tfsec is installed from its release with the checksum checked rather than through the marketplace action, which defaults to soft fail. When tfsec finds anything at HIGH or above it exits with code 1, the step fails, and so does the job. Branch protection on `main` lists `tfsec (HIGH and above)` as a required status check next to Lab 4's `summary` (`evidence/required-status-checks.json`), so GitHub refuses to merge while that check is red. Pull request #40 shows both states: with the broken file the check failed and the PR was `BLOCKED` (`pr-checks-blocked.txt`, `pr-mergeable-blocked.json`; `pr-blocked.png` shows the same blocked state on throwaway PR #41, which put the open SSH rule back and was closed without merging); after the fix it passed and the PR became `CLEAN` (`pr-checks-passing.txt`, `pr-mergeable-passing.json`, `pr-passing.png`). The workflow has no `paths:` filter on purpose: a required check has to report on every pull request, or PRs that don't touch `lab8/` would wait for it forever. The check stays enabled for the Final Project, and since then the same job has a second step that scans `final-project/terraform` too, so the check's name and its place in branch protection haven't changed. As the repository admin I still see a "bypass rules" checkbox on a blocked PR, because "Do not allow bypassing the above settings" is off; I never use it, and on a team repository that setting would be on so the gate binds admins too.

## The one suppression I kept

I suppressed `aws-ec2-no-public-egress-sgr` (CRITICAL) on one rule, `aws_security_group_rule.https_out`, which lets the host make outbound HTTPS connections (port 443 only) to any address. The host needs that to reach the Amazon Linux package repositories for `dnf` updates and the Systems Manager endpoints for the SSM agent, and neither has a fixed address range I could list instead. The risk I'm accepting is that something running on the host could send data out over HTTPS; nothing on the internet can open a connection in through this rule, and every other port, in and out, stays closed. In production I'd replace it with VPC endpoints for SSM and S3 plus an egress proxy, and the review date is 2026-12-31. The `#tfsec:ignore:aws-ec2-no-public-egress-sgr` comment sits on the line directly above the rule, with the reason, my name (`jhui26-seneca`) and the date on the lines above it, and it is the only `tfsec:ignore` in the folder (`tfsec-ignores.txt`, where the every-severity scan shows `ignored 1`).

## LabRole vs voclabs

LabRole is the role behind the workstation's instance profile: the CLI and Terraform on the workstation get its credentials from the instance metadata service, which renews them automatically for as long as the instance runs. voclabs is the role behind the Vocareum session, the one whose keys I copy from "AWS CLI: Show" into the GitHub secrets for CI. I ran the same 11 calls as both (`labrole-vs-voclabs.txt`), and in this account they behaved the same: both can read EC2, SSM, S3, CloudTrail and IAM roles, both can launch a t3.micro (dry run), both can create an IAM policy, and both are refused `iam:CreateRole` and Access Analyzer with "no identity-based policy allows". The handout expects `aws iam create-policy` to be denied; here it isn't. LabRole created `acs730-lab8-deploy-policy`, and I deleted it straight away (`iam-create-policy-labrole.txt`), so the AccessDenied I capture is the next step, creating a role to attach the policy to (`iam-create-policy-accessdenied.txt`). What differs is what's attached and where the credentials come from. LabRole carries three VocLabPolicy policies plus AWS-managed SSM, EKS and ECR policies, meant for services that run as it; voclabs carries `Pvoclabs1`, `Pvoclabs2` and `voc-cancel-cred`, and neither role is allowed to read those documents (LabRole is blocked by an explicit deny in VocLabPolicy2, the voclabs policies by the Academy's service control policy). That explains "works locally, fails in CI": the workstation's LabRole credentials keep renewing, while the voclabs keys in GitHub belong to one Academy session and stop working when it ends or restarts (judging by its name, `voc-cancel-cred` is how Vocareum revokes an old session's keys). The same command then succeeds on the workstation and fails in CI with `ExpiredToken`, which is why every lab session since Lab 3 starts with `refresh-gha-creds.sh`.

## Supporting notes

**Least privilege.** `policies/lab8-deploy-policy.json` replaces PowerUserAccess (every action except IAM and Organizations, on every service) with what the plan needs (`plan-resources.txt`: one security group, two rules, one instance). It has four statements: read anything in EC2 so Terraform can plan and refresh (`ec2:Describe*` plus `sts:GetCallerIdentity`); create the security group, its rules and the instance only in `us-east-1`; tag only while creating; and change or delete only resources tagged `Lab = lab8`, which the provider's `default_tags` put on everything this file creates. There's no IAM, no `iam:PassRole` (the instance has no profile) and no S3 (no remote state). I stopped there. The next step would limit `RunInstances` to `t3.micro` and one AMI, which needs a separate statement for each resource type in the request, and I'd only do that in an account where I could test it, since the Academy won't let me attach the policy to anything.

**Secrets in git history.** `gitleaks git --redact --log-opts=--all` found three `generic-api-key` matches, all `KEY_NAME="acs730-lab2-key"` in Lab 2 scripts (commit `86d1144`). That's the name of an EC2 key pair, not a secret, so they are false positives; I recorded their fingerprints with the reason in `.gitleaksignore` at the repository root instead of changing Lab 2, which is already graded, and the second scan exits 0 (`gitleaks-history.txt`, `gitleaks-report.json`). `git log --all --name-only` still lists `midterm-practice/terraform/terraform.tfstate`, and the same starter commit (`acffcc0`) had `AKIAIOSFODNN7EXAMPLE` in `midterm-practice/scripts/deploy.sh`. Both came from the midterm practice starter repository: the state file is from LocalStack (account `000000000000`), and the key is AWS's published documentation example, so there is nothing to rotate. I removed both in `6bc40bc` and chose not to rewrite history, because that means force-pushing `main` and changing the SHA of every commit since, including the Lab 7 commits whose SHAs are the deployed image tags in its evidence. With a real credential the order would be: rotate it first, then rewrite history.

**Checkov for comparison.** Checkov 3.4.3 failed 6 checks on the broken file and 3 on the fixed one (`checkov-before.txt`, `checkov-after.txt`). It agrees on SSH, encryption and IMDS, never flags the open egress rule, and still fails detailed monitoring, EBS optimisation and the missing IAM role, which I accept for a planned-only lab host. tfsec is the gate.

## Files

| File | What it is |
|---|---|
| `main.tf` | The fixed configuration: SSH from one `/32`, encrypted root volume, IMDSv2, one justified `tfsec:ignore` |
| `.terraform.lock.hcl` | Provider lock file from `terraform init` |
| `policies/lab8-deploy-policy.json` | The scoped deploy policy |
| `../.github/workflows/lab8-policy.yml` | The `tfsec (HIGH and above)` gate |
| `../.gitleaksignore` | The three gitleaks false positives, each with its reason |

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/compare-identities.sh` | `evidence/labrole-vs-voclabs.txt` | Nothing. Every call is read-only, a `--dry-run`, or sends an empty document so an allowed IAM create fails validation and creates nothing | A voclabs credentials file kept outside the repository, shredded afterwards | Workstation |

| Workflow | Runs on | Trigger | What it changes |
|---|---|---|---|
| `lab8-policy.yml` | `ubuntu-latest` | Every pull request, push to `main`, manual | Nothing; it installs tfsec and scans `lab8/`, and needs no AWS credentials. Since the Final Project, a second step in the same job also scans `final-project/terraform` |

Nothing in this folder is applied to AWS. `terraform plan` was run with the workstation's LabRole only to derive the policy.

## Evidence

| File | Shows |
|---|---|
| `caller-identity.png` | Workstation identity at the start |
| `tfsec-all-severities.txt`, `tfsec-before.txt` | The four findings on the broken file, exit code 1 |
| `checkov-before.txt`, `checkov-after.txt` | Checkov on the broken and fixed file |
| `required-status-checks.json` | `summary` and `tfsec (HIGH and above)` required on `main` |
| `pr-checks-blocked.txt`, `pr-mergeable-blocked.json`, `pr-blocked.png` | PR #40 red and `BLOCKED` |
| `tfsec-after.txt` | `No problems detected`, exit code 0 |
| `tfsec-ignores.txt` | Exactly one `tfsec:ignore`, with its reason |
| `pr-checks-passing.txt`, `pr-mergeable-passing.json`, `pr-passing.png` | PR #40 green and `CLEAN` |
| `plan-resources.txt` | What the plan would create, the input to the policy |
| `iam-create-policy-labrole.txt` | LabRole allowed to create the policy, and its deletion |
| `iam-create-policy-accessdenied.txt` | `AccessDenied` on `iam:CreateRole` for voclabs and LabRole |
| `labrole-vs-voclabs.txt` | The same 11 calls as both identities |
| `gitleaks-history.txt`, `gitleaks-report.json` | Full-history secret scan (redacted), the history file list, and the scan with `.gitleaksignore` |
