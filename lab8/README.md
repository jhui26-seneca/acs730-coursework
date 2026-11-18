# Lab 8: Security and policy as code

`lab8/main.tf` describes a small web host in the default VPC (a security group, its two rules and one t3.micro). It is only ever scanned and planned, never applied, and `tfsec lab8 --minimum-severity HIGH` exits 0 on it as a required check on `main`. The files and evidence are listed first; the four paragraphs the walkthrough asks for are under **Security controls and what they caught**, followed by the experiments.

## Files

| File | What it is |
|---|---|
| `main.tf` | The fixed configuration: SSH from one `/32`, encrypted root volume, IMDSv2, one signed `tfsec:ignore` |
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
| `tfsec-all-severities.txt`, `tfsec-before.txt` | The findings on the broken file, with rule IDs, exit code 1 |
| `checkov-before.txt`, `checkov-after.txt` | Checkov (optional second opinion) on the broken and fixed file |
| `required-status-checks.json` | `summary` and `tfsec (HIGH and above)` required on `main` |
| `pr-checks-blocked.txt`, `pr-mergeable-blocked.json`, `pr-blocked.png` | The check red and the pull request `BLOCKED` |
| `tfsec-after.txt` | `No problems detected`, exit code 0 |
| `tfsec-ignores.txt` | Exactly one `tfsec:ignore`, with its reason |
| `pr-checks-passing.txt`, `pr-mergeable-passing.json`, `pr-passing.png` | Pull request #40 green and `CLEAN` |
| `plan-resources.txt` | What the plan would create, the input to the policy |
| `iam-create-policy-labrole.txt` | LabRole allowed to create the policy in this account, and its deletion |
| `iam-create-policy-accessdenied.txt` | `AccessDenied` on `iam:CreateRole` for voclabs and LabRole |
| `labrole-vs-voclabs.txt`, `labrole-vs-voclabs-wide.txt` | 11 and then 33 more calls run as both identities |
| `gitleaks-history.txt`, `gitleaks-report.json` | Full-history secret scan (redacted), the history file list, and the scan with `.gitleaksignore` |

## Security controls and what they caught

These are the four paragraphs the walkthrough asks for, one per numbered heading.

### 1. The required check that guards `main`

`.github/workflows/lab8-policy.yml` runs one job, shown as `tfsec (HIGH and above)`, on every pull request and every push to `main`. Its gate step is `tfsec lab8 --minimum-severity HIGH --no-color`, with no `|| true`, no `continue-on-error` and no `soft_fail`. Any HIGH or CRITICAL finding makes tfsec exit 1 and fails the job. It needs no AWS credentials, because tfsec only reads the HCL on disk.

The job is a required status check on `main`, next to Lab 4's `summary`. It's in the classic branch protection rule for `main` (Settings, Branches, Branch protection rules, `main`, "Require status checks to pass before merging"). I added it with `gh api` (POST to the rule's `required_status_checks/contexts`) once it had reported on pull request #40, and the receipt is `evidence/required-status-checks.json`.

The workflow has no `paths:` filter on purpose (Experiment 3 below shows why), and the rule stays on for the Final Project.

### 2. The misconfiguration, the block and the fix

Commit `29c5931` on pull request #40 broke `lab8/main.tf` in two unrelated ways:

- SSH open to the world (`cidr_blocks = ["0.0.0.0/0"]` on port 22, rule `aws-ec2-no-public-ingress-sgr`, CRITICAL)
- an unencrypted root volume (`encrypted = false`, rule `aws-ec2-enable-at-rest-encryption`, HIGH)

It also left IMDSv1 on (`aws-ec2-enforce-http-token-imds`, HIGH). `evidence/tfsec-before.txt` shows the findings with their rule IDs and exit code 1.

With `0.0.0.0/0`, every internet scanner can reach `sshd` within minutes and try passwords, stolen keys or an unpatched exploit. With a `/32`, only my one address can even open the connection. An unencrypted volume costs you the day a snapshot is shared or copied, or a disk is recovered: whoever holds the copy can read it, whereas an encrypted one also needs permission on the KMS key.

The merge was prevented, not merely flagged. The check went red and GitHub reported the pull request `BLOCKED` (`evidence/pr-checks-blocked.txt`, `evidence/pr-mergeable-blocked.json`). `evidence/pr-blocked.png` shows the same blocked state on throwaway pull request #41, which put the open SSH rule back and was closed without merging.

The fix, commit `d8b7465` on the same pull request, changed `cidr_blocks` back to `[var.admin_cidr]` (a variable whose validation only accepts a `/32`), set `encrypted = true`, and added `http_tokens = "required"`. `evidence/tfsec-after.txt` says "No problems detected!" with exit code 0, and the pull request went `CLEAN` (`evidence/pr-checks-passing.txt`, `evidence/pr-mergeable-passing.json`, `evidence/pr-passing.png`). It was merged with `--merge`, so the breaking and the fixing commit are both on `main`.

### 3. The deploy policy, the one ignore and the secret scan

`policies/lab8-deploy-policy.json` replaces PowerUserAccess with what the plan needs (`evidence/plan-resources.txt`). Here are three things PowerUserAccess allows that it doesn't:

- any service at all: a pipeline with PowerUserAccess could create an RDS database, a Lambda function or an S3 bucket, while mine only reaches EC2
- any region: mine creates only in `us-east-1`
- changing or deleting any instance or security group in the account, including my workstation: mine only touches resources tagged `Lab = lab8`

The walkthrough expects `aws iam create-policy` to be refused. In this Academy account it was allowed, so I deleted the policy straight away (`evidence/iam-create-policy-labrole.txt`) and captured the refusal one step later: creating the role the policy would attach to was denied with `AccessDenied` for `assumed-role/LabRole` and for voclabs (`evidence/iam-create-policy-accessdenied.txt`). That denial is the expected outcome, not a failure. The Learner Lab lets students write IAM documents but not give them to anything.

The one suppression, `#tfsec:ignore:aws-ec2-no-public-egress-sgr` (CRITICAL), sits directly above `aws_security_group_rule.https_out`. That rule lets the host make outbound HTTPS connections to any address, because the Amazon Linux package repositories and the SSM endpoints have no fixed address ranges; nothing can connect in through it. I signed it as `jhui26-seneca` on 2026-11-12 with a review date of 2026-12-31, and it's the only ignore in the folder (`evidence/tfsec-ignores.txt`). I'd remove it once SSM and S3 VPC endpoints plus an egress proxy are in place.

The secret scan was `gitleaks git --redact --log-opts="--all"`, which read all 75 commits of history on every branch rather than the working tree. It exited 1 with three `generic-api-key` findings in Lab 2 scripts. All three were the name of an EC2 key pair, not a key, so I recorded them by fingerprint with that reason in `../.gitleaksignore`, and the rescan exited 0 (`evidence/gitleaks-history.txt`, `evidence/gitleaks-report.json`).

### 4. LabRole versus voclabs: where each environment gets its identity

My three environments run as three different things:

- The workstation calls AWS as LabRole, through its instance profile, with credentials the metadata service keeps renewing.
- The Vocareum console and any CLI configured from the AWS Details keys act as voclabs.
- A GitHub runner has no AWS identity at all until `refresh-gha-creds.sh` copies a voclabs session into the repository secrets, and those keys die when the Academy session ends. The Lab 8 tfsec job never gets one, because it doesn't need one.

The two roles carry different policies (LabRole: VocLabPolicy1 to 3 plus the AWS-managed SSM, EKS and ECR policies; voclabs: `Pvoclabs1`, `Pvoclabs2` and `voc-cancel-cred`), and neither is allowed to read the other's documents.

I ran 44 identical calls as both (`evidence/labrole-vs-voclabs.txt`, `evidence/labrole-vs-voclabs-wide.txt`). In this account they were allowed or refused alike, though sometimes by different layers: `ec2:DescribeInstances` in `eu-west-1` is refused for LabRole by the service control policy and for voclabs because none of its own policies allows it.

So the "works locally, fails in CI" difference here is where the credentials come from and how long they last. `aws sts get-caller-identity` succeeds on the workstation at any time. In CI it fails with "Unable to locate credentials" in a job like the tfsec one, and with `ExpiredToken` once the session whose keys are in the secrets has ended. My own receipt is a worked example of a refusal: `iam:CreateRole` denied to `assumed-role/LabRole`.

Calls 1 to 11 are from November 12 (`evidence/labrole-vs-voclabs.txt`) and 12 to 44 from November 18 (`evidence/labrole-vs-voclabs-wide.txt`). Every call is read-only, a `--dry-run`, or sends an empty document, so nothing was created. Each verdict shows which layer answered: "no policy allows" is the role's own policies, "explicit deny" a Deny statement in them, and "SCP" the Academy's service control policy over the whole account.

| # | Call | LabRole (workstation) | voclabs (console, CLI keys, CI) |
|---|---|---|---|
| 1 | `ec2 describe-vpcs` | ALLOWED | ALLOWED |
| 2 | `ec2 run-instances t3.micro (--dry-run)` | ALLOWED (dry run) | ALLOWED (dry run) |
| 3 | `ssm describe-parameters` | ALLOWED | ALLOWED |
| 4 | `s3api list-buckets` | ALLOWED | ALLOWED |
| 5 | `cloudtrail lookup-events` | ALLOWED | ALLOWED |
| 6 | `iam get-role LabRole` | ALLOWED | ALLOWED |
| 7 | `iam list-attached-role-policies LabRole` | ALLOWED | ALLOWED |
| 8 | `iam list-attached-role-policies voclabs` | ALLOWED | ALLOWED |
| 9 | `iam create-policy (empty document)` | ALLOWED (reached validation) | ALLOWED (reached validation) |
| 10 | `iam create-role (empty trust policy)` | DENIED (no policy allows it) | DENIED (no policy allows it) |
| 11 | `access-analyzer validate-policy` | DENIED (no policy allows it) | DENIED (no policy allows it) |
| 12 | `lambda list-functions` | ALLOWED | ALLOWED |
| 13 | `rds describe-db-instances` | ALLOWED | ALLOWED |
| 14 | `eks list-clusters` | ALLOWED | ALLOWED |
| 15 | `ecr describe-repositories` | ALLOWED | ALLOWED |
| 16 | `ecs list-clusters` | ALLOWED | ALLOWED |
| 17 | `cloudformation list-stacks` | ALLOWED | ALLOWED |
| 18 | `dynamodb list-tables` | ALLOWED | ALLOWED |
| 19 | `sns list-topics` | ALLOWED | ALLOWED |
| 20 | `sqs list-queues` | ALLOWED | ALLOWED |
| 21 | `kms list-keys` | ALLOWED | ALLOWED |
| 22 | `secretsmanager list-secrets` | ALLOWED | ALLOWED |
| 23 | `logs describe-log-groups` | ALLOWED | ALLOWED |
| 24 | `cloudwatch describe-alarms` | ALLOWED | ALLOWED |
| 25 | `events list-rules` | ALLOWED | ALLOWED |
| 26 | `elbv2 describe-load-balancers` | ALLOWED | ALLOWED |
| 27 | `autoscaling describe-auto-scaling-groups` | ALLOWED | ALLOWED |
| 28 | `route53 list-hosted-zones` | ALLOWED | ALLOWED |
| 29 | `cloudtrail describe-trails` | ALLOWED | ALLOWED |
| 30 | `config describe-config-rules` | ALLOWED | ALLOWED |
| 31 | `guardduty list-detectors` | ALLOWED | ALLOWED |
| 32 | `organizations describe-organization` | DENIED | DENIED |
| 33 | `iam list-users` | ALLOWED | ALLOWED |
| 34 | `iam list-roles` | ALLOWED | ALLOWED |
| 35 | `iam get-account-summary` | ALLOWED | ALLOWED |
| 36 | `iam list-policies (local)` | ALLOWED | ALLOWED |
| 37 | `iam get-policy-version (a VocLabPolicy)` | DENIED (explicit deny) | DENIED (explicit deny) |
| 38 | `ssm describe-instance-information` | ALLOWED | ALLOWED |
| 39 | `ce get-cost-and-usage (billing)` | ALLOWED | ALLOWED |
| 40 | `ec2 describe-instances in eu-west-1` | DENIED (SCP) | DENIED (no policy allows) |
| 41 | `ec2 describe-instances in us-west-2` | ALLOWED | ALLOWED |
| 42 | `ec2 run-instances with LabInstanceProfile (--dry-run)` | ALLOWED (dry run) | ALLOWED (dry run) |
| 43 | `ec2 run-instances t3.2xlarge (--dry-run)` | DENIED (explicit deny) | DENIED (explicit deny) |
| 44 | `ec2 create-vpc (--dry-run)` | ALLOWED (dry run) | ALLOWED (dry run) |

## Experiments (optional, not on the hand-in list)

**1. Lower the gate to MEDIUM.** Locally, tfsec at MEDIUM found nothing and exited 0, the same as at HIGH, and a scratch pull request (#60, closed unmerged) whose workflow scanned `lab8/` at MEDIUM went green and `CLEAN`. After the fix this configuration has no MEDIUM or LOW findings at all, so the bar made no difference, and my signed ignore played no part, since it suppresses a CRITICAL rule. A team still gates at HIGH and reports LOW weekly, because a gate that fails on every low-grade finding gets bypassed, while a weekly report keeps those findings visible without stopping work.

**2. Make the ignore blanket.** With the signed ignore, tfsec on every severity showed `passed 7, ignored 1`; with `#tfsec:ignore:*` it showed `passed 6, ignored 2`, and still "No problems detected!". The blanket version silenced a second rule on that resource, one that was passing, so it hides every future finding there too, and nothing in the output tells a reviewer anything changed. That makes it worse than no ignore: with none, the finding is at least visible and somebody has to decide about it.

**3. Break the path filter.** A scratch pull request (#61, closed unmerged) gave `pull_request` a `paths: ['lab7/**']` filter and changed a line under `lab8/`. The tfsec check never ran, and even 60 seconds later GitHub listed no tfsec result at all and kept the pull request `BLOCKED`, waiting on a required check that would never report. A required check that never runs isn't passing, it's missing, which is why my workflow has no `paths:` filter.

**4. Ask AWS to grade the policy.** `aws accessanalyzer validate-policy` on `lab8-deploy-policy.json` was refused for both LabRole and voclabs with "no identity-based policy allows the access-analyzer:ValidatePolicy action". In this account AWS won't review a policy for me, so the review has to happen before AWS: JSON validation, reading it against the plan, and tools in the pipeline.

**5. History versus working tree.** The walkthrough's sample key, which ends in `EXAMPLEKEY`, gave "no leaks found" (exit 0) when scanned with `--no-git`, because gitleaks deliberately ignores AWS's published example keys; a random-looking key in the same place was caught at once (`generic-api-key`, exit 1). A `--no-git` scan of this repository's working tree found 5 matches (exit 1): the three Lab 2 scripts, plus `.gitleaksignore` and an earlier version of this README, which quoted the same line, so writing about a false positive made two more. The history scan of the same repository exited 0, because `.gitleaksignore` entries are tied to commit fingerprints. And a working-tree scan says nothing about a key committed in Week 2 and deleted in Week 3: it only sees the files as they are now, while the key is still in the Week 2 commit for anyone with a clone.
