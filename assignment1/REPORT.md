# Assignment 1 - Multi-Environment Infrastructure Deployment with Terraform

**Report** - John Hui (GitHub `jhui26-seneca`), ACS730, October and November 2026. Repository: `jhui26-seneca/acs730-coursework`, folder `assignment1/`. File-by-file details and scripts are in `README.md`; every claim below points to a file in `evidence/`.

## Introduction

The aim of this assignment was to take the single Terraform configuration I wrote in Lab 5 and run it the way a team would run production infrastructure: one reusable module, three environments that cannot interfere with each other, a pipeline that deploys staging on every merge but puts a named person in front of prod, credentials that only the right job can read, an application secret that never appears in code, and an alarm that watches the result.

All of it ran in an AWS Academy Learner Lab account, which shaped three decisions. First, the IAM writes that OIDC needs are denied, so OIDC federation - the correct way for GitHub Actions to reach AWS - can be designed but not built; the pipeline uses session-scoped Academy credentials instead, scoped to GitHub Environments. Second, the budget is fixed, so every environment was created and destroyed within the same session. Third, the account is shared with platform automation I do not control, which turned out to matter: midway through the first prod deployment the Academy stopped every instance in the account. How that was diagnosed and recovered is part of Task 5.

The work was first delivered in October through three pull requests: #25 (module, dev, LocalStack check, GitHub Environments), #26 (staging and prod, the gated deploy workflow, environment-scoped secrets) and #27 (prod resized to `t3.micro` for the re-deployment). In November the final project reused this module, and its brief requires a security scan that blocks merges, so I hardened the module (PRs #47 and #48) and re-ran the whole assignment, dev to teardown, on 13 November. Every file in `evidence/` comes from that re-run; the October run is described in Task 5 because of what it taught me.

## Task 1 - A reusable module

The module `terraform/modules/web-env/` started as a copy of my Lab 5 files (`lab5/` itself is untouched) and builds one complete environment: a VPC, two public subnets created with `for_each`, an internet gateway and route table, an HTTP-only security group, a web server with an encrypted root volume, two CloudWatch alarms, and a data source that reads the database password.

Choosing the inputs came down to one question: what actually differs between environments? Those became variables - `environment`, `vpc_cidr`, `instance_type`, `detailed_monitoring`, `cpu_alarm_threshold`, `alarm_evaluation_periods` and `db_password_parameter_name` - each typed, described and validated (for example `vpc_cidr` must be a valid CIDR and `instance_type` must be `t3.micro` or `t3.small`). Values that are the same everywhere stay inside the module as locals or defaults, such as the name prefix `acs730-assign1-<environment>`, the subnet layout and the AMI filter. `vpc_cidr` and `cpu_alarm_threshold` deliberately have no defaults, so a copied environment cannot silently reuse dev's network range. The `ingress_rules` variable carries a validation that refuses port 22, which makes the "no SSH" rule fail at plan time instead of relying on review.

Three things moved out of the Lab 5 code. The S3 bucket went, because the Academy account denies a read the Terraform provider makes after creating any bucket (found in Lab 6). The provider, default tags and backend went to the callers, because a module should not decide where it deploys or where its state lives. Port 443 went because nothing listens on it. Two things were added: `LabInstanceProfile` with IMDSv2 only, so Session Manager is the only way into the instance, and the outputs a caller needs - IDs, the URL, the alarm names and the parameter version, with the password output marked `sensitive`.

**The November hardening.** tfsec found seven issues in the October module, six of them CRITICAL or HIGH. I fixed one and accepted three by design, and I changed the security group so that accepting them could not hide anything else:

| tfsec finding | What I did |
|---|---|
| `aws-ec2-enable-at-rest-encryption` (HIGH): root volume not encrypted | Fixed: `root_block_device { encrypted = true, volume_size = 8 }`, with the account's default EBS key. It costs nothing |
| `aws-ec2-no-public-ingress-sgr` (CRITICAL): port 80 open to the internet | Accepted: it's a public web page and the only public inbound rule |
| `aws-ec2-no-public-egress-sgr` (CRITICAL): all outbound to the internet | Accepted: `dnf` and the SSM agent need outbound HTTPS to addresses with no fixed range. Nothing can connect in through an outbound rule |
| `aws-ec2-no-public-ip-subnet` (HIGH): subnets give out public IPs | Accepted: the page must be reachable, and a NAT gateway would cost about $33 a month |
| `aws-ec2-require-vpc-flow-logs-for-all-vpcs` (MEDIUM) | Left as a finding: below the HIGH gate, and the logs would cost money for traffic nobody reviews |

Each accepted finding has a `#tfsec:ignore` directly above the one resource it covers, with the reason, my name, the date and a review date above it. The October security group built every rule inline with a `dynamic` block, so a suppression would have covered the whole group, including any port a caller later added. Now each rule is its own `aws_security_group_rule`, and the rules a caller passes in `ingress_rules` (default: none) go to `extra_ingress`, which is never suppressed. Before committing I opened port 8080 to `0.0.0.0/0` in a caller as a test: tfsec reported it as CRITICAL on `extra_ingress` and exited 1.

## Task 2 - Three environment directories

| | dev | staging | prod |
|---|---|---|---|
| State key | `assign1/dev/terraform.tfstate` | `assign1/staging/terraform.tfstate` | `assign1/prod/terraform.tfstate` |
| VPC | `10.10.0.0/16` | `10.20.0.0/16` | `10.30.0.0/16` |
| Instance | `t3.micro` | `t3.micro` | `t3.micro` |
| Metrics / alarm period | 5-minute / 300 s | 1-minute / 60 s | 1-minute / 60 s |
| CPU alarm threshold | 80% | 70% | 60% |
| Deployed by | `scripts/create-dev.sh` on my workstation | pipeline, on every merge | pipeline, after approval |

Each directory contains the same four small files - `versions.tf` with its own backend key, `providers.tf` with its own `Environment` tag, `main.tf` calling the module, and `outputs.tf` - and the three `main.tf` files differ only in the values they pass. I wrote each key as part of creating the directory rather than copying `dev/` and editing afterwards, and checked them before any apply: `grep` showed three different keys, and the first workstation plan for staging and for prod each said `10 to add, 0 to destroy` (13 since the November changes). `evidence/backend-state-keys.txt` shows the result in the shared bucket: three objects, `assign1/dev`, `assign1/staging` and `assign1/prod`, each with its own size and timestamp. One bucket, three keys means one place to manage encryption and versioning, but no way for a plan in one environment to see, or destroy, another's resources.

A fourth caller, `terraform/ci-localstack/`, applies the same module to LocalStack on every pull request with no backend and no AWS credentials. It caught a real limit of emulation: LocalStack does not implement EC2 `MonitorInstances`, so that caller turns detailed monitoring off. It caught another in November. Once the module set `root_block_device`, LocalStack's `RunInstances` demanded a volume size, which real AWS takes from the image. A green LocalStack check proves the module is coherent; it does not prove every AWS feature it uses will work, which is why staging exists. And the reverse is also true: the November failure was a LocalStack limit, not a fault in the module, and dev had already built the same code on real AWS.

## Task 3 - GitHub Environments

`scripts/configure-environments.sh` creates both environments through the GitHub API, and `evidence/environments.json` is the API's record of them. `staging` has no protection rules: a merge to `main` deploys it with nobody involved. `prod` has a required reviewer (me) and a deployment branch policy that allows only `main`. Because I am the only person on the repository, "prevent self-review" is off; in a team it would be on, so the person merging could not also approve their own production change.

In the deploy workflow each job names its environment (`environment: staging` and `environment: prod`), and the `prod` job also `needs: staging`, so prod can only start after staging has succeeded and a reviewer has released it.

## Task 4 - Scoped credentials and the OIDC trust policy

### What was done

The three AWS secrets now exist only on the two environments. `./scripts/refresh-gha-creds.sh jhui26-seneca/acs730-coursework staging prod` wrote them to `staging` and `prod`, then `scripts/delete-repo-secrets.sh` deleted the repository-level copies - it refuses to run unless both environments already hold all three, so the pipeline is never left with no credentials. `evidence/secrets-scope.txt`, captured straight afterwards, shows `RESULT: no AWS_* secret at repository level` and the three names under each environment; `AWS_REGION` stays a repository variable because it is not a secret. I deleted the repository copies before merging the deploy workflow on purpose: the successful deployment that followed could only have read environment secrets. From now on the per-session refresh is the three-argument form above.

### The trust policy I would deploy in a real account

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowOnlyProdEnvironmentJobsFromThisRepo",
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::572751986246:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:jhui26-seneca/acs730-coursework:environment:prod"
        }
      }
    }
  ]
}
```

This would be the trust policy of a role used only by the prod job, for example `acs730-assign1-prod-deploy`. Condition by condition:

- **`Principal.Federated`** - only tokens issued by GitHub's OIDC provider, registered in this account, are considered at all. A token from any other identity provider, or an IAM user's access key, cannot use this role.
- **`Action: sts:AssumeRoleWithWebIdentity`** - the only way in is exchanging a signed, short-lived web-identity token. There is no access key to store, copy, leak or rotate.
- **`aud = sts.amazonaws.com`** - the token must have been minted for AWS STS. A GitHub token minted for some other service, and replayed against AWS, is refused.
- **`sub = repo:jhui26-seneca/acs730-coursework:environment:prod`** (`StringEquals`, an exact match) - this is the condition that matters most. GitHub only puts `environment:prod` into the token's subject when the job declares `environment: prod`, and GitHub only starts such a job when the environment's rules are satisfied: the branch is `main` and the required reviewer has approved. The trust policy therefore inherits the review gate. A job on a feature branch, a pull request, or a workflow that does not name the environment receives a token whose subject is something like `repo:jhui26-seneca/acs730-coursework:ref:refs/heads/my-branch`, which does not match, so STS refuses it.

The loose version, `"StringLike": {"...:sub": "repo:jhui26-seneca/acs730-coursework:*"}`, matches every token the repository can produce. Under it, anyone with push access to any branch could add a workflow step - say `terraform destroy` against prod, or `aws s3 cp` of the state bucket - push the branch, and the job would assume the prod role without a pull request, a review or a merge. The required reviewer would still exist in GitHub's settings, but AWS would no longer be relying on it. Scoping `sub` to the environment makes the reviewer part of the access-control decision instead of a convention people are trusted to follow. The remaining trust is in whoever can change the environment's settings in GitHub, which is why repository admin rights and changes to `.github/workflows/` should themselves be restricted. Staging would get its own role with `sub` ending in `environment:staging`, so a bug in staging automation cannot reach prod, and both roles would carry least-privilege permission policies rather than the broad access LabRole has.

### Why it was not deployed

AWS Academy denies the IAM writes this design needs: `iam:CreateOpenIDConnectProvider` and `iam:CreateRole` (the course demonstrated the `AccessDenied` in Week 3, and I saw `iam:CreateRole` refused again in Lab 8, for both LabRole and voclabs), so neither the provider nor the role can exist in this account. Not every IAM write is refused, though: in Lab 8, `iam:CreatePolicy` was allowed. A policy with no role to attach it to grants nothing, so that doesn't change the conclusion. The substitute is bounded in two ways: the credentials are Academy session credentials that stop working within about four hours, and environment-scoped secrets reproduce the effect of the `sub` condition - only a job that declares `environment: prod`, which GitHub starts only from `main` after approval, can read the prod copy.

## Task 5 - Deploying to real AWS

The pipeline is `.github/workflows/assign1-deploy.yml`: on a push to `main` that touches `assignment1/` (evidence and Markdown excluded), job `staging` runs init, plan, apply and a smoke test that fetches the page; job `prod` then waits for approval and does the same. Pull requests never touch AWS; they get the credential-free LocalStack check.

**The evidence run (PR #48, run 43529808689, 13 November).** Staging deployed itself with no approval step: created 23:48:20 UTC, started 4 seconds later, `Plan: 13 to add`, `Apply complete! Resources: 13 added`, and the smoke test returned `ACS730 assign1 - staging` (`evidence/staging-apply.txt`). The prod job stopped at the gate as designed. The deployment history in `evidence/prod-apply.txt` shows `waiting` at 23:50:07, `queued` at 23:55:43 when I approved, `in_progress` 23:55:45 and `success` 23:57:22, with the approval recorded above it: approved by `jhui26-seneca`, environment `prod`, comment "Assignment 1 module hardening, staging verified". The job ran `Plan: 13 to add` and `Apply complete! Resources: 13 added`, and its smoke test returned `ACS730 assign1 - prod`. `evidence/prod-approval-pending.png` and `evidence/prod-approval-approved.png` show the same run before and after the approval. This time I approved on the strength of staging, which had just applied the same commit with the same 13-resource plan; in October I had also read prod's own plan from the workstation first, which is the better habit (see the Conclusion).

**The run that isn't the evidence.** The first November merge, PR #47, went through with its LocalStack check red (Task 2), because that check isn't required. Its staging job deployed. I cancelled the run before approving prod (run 43528042983) and destroyed staging, fixed the module in PR #48, and merged that only after every check was green. Deploying prod from a commit whose checks had failed would have meant the evidence showed a pipeline I wouldn't trust.

**The October run, and what it showed.** The first merge (PR #26, run 38853932149) deployed staging in 1 minute 37 seconds. About two minutes after I approved prod, at 05:14 UTC, all four running instances (workstation, dev, staging and the new prod) were stopped. The state reason was `Client.UserInitiatedShutdown`, meaning an API call, so I looked it up in CloudTrail: three `StopInstances` events by `assumed-role/vocareum/resource`, the Academy's own management role. Nothing in my scripts or workflows calls `StopInstances`, and the account was within the published Learner Lab limits, so the cause was on the platform side. Recovery needed no pipeline changes: I destroyed the half-finished prod, restarted staging, set prod to `t3.micro`, read the new prod plan, and merged again (PR #27, run 38857506268), which deployed prod through the same gate with a new approval.

## Task 6 - Secrets management

The application value is a placeholder database password per environment, stored as a `SecureString` in SSM Parameter Store and created once, out of band, before anything plans. The documented pre-step, run from the workstation (it is what `scripts/create-ssm-parameters.sh` does for each environment):

```bash
aws ssm put-parameter --region us-east-1 \
  --name /acs730/assign1/prod/db_password \
  --type SecureString \
  --value "placeholder-not-a-real-password-prod" \
  --tags "Key=Course,Value=ACS730" "Key=Assignment,Value=assign1" "Key=Environment,Value=prod"
```

Terraform only reads it, with `data "aws_ssm_parameter" "db_password"` and `with_decryption = true` in `modules/web-env/secrets.tf`; there is no `aws_ssm_parameter` resource anywhere, because creating and reading the same name in one graph fails on a fresh environment, which is exactly what CI always is. The value goes into the instance's user data, which writes it to `/etc/acs730/app.env` (owner root, mode 0600) for the application; the web page only reports which parameter and version were loaded. Because the data source marks the value sensitive, Terraform printed `user_data = (sensitive value)` in every plan, locally and in the pipeline logs. `evidence/ssm-parameter.txt` puts the two sides next to each other: AWS holds `placeholder-not-a-real-password-prod`, version 1, and Terraform's output from the prod state is the same value and version. On dev I also checked through SSM Run Command, with no SSH, that the file exists and is `-rw------- root root`.

The trade-offs are worth stating. A value read by a data source is still written to the Terraform state, which is why the state lives in an encrypted, versioned bucket and never in Git. It is also visible in the instance's user data to anyone allowed `ec2:DescribeInstanceAttribute`. For a real password I would pass only the parameter name and have the application fetch it at runtime with its instance role, or use Secrets Manager, which adds rotation.

## Task 7 - The CloudWatch alarms

`modules/web-env/monitoring.tf` defines two alarms per environment. The first, the one Task 7 asks for, is on the instance's `AWS/EC2` `CPUUtilization`: average above the environment's threshold for 3 consecutive periods. CPU utilisation was chosen because an idle instance still reports it; a request-count metric on a page nobody visits would never leave `INSUFFICIENT_DATA`. The period follows `detailed_monitoring` - 60 seconds in staging and prod, 300 seconds in dev - because an alarm with a shorter period than its metric never receives a datapoint. Missing data is treated as missing, so the alarm cannot show a false `OK`.

The second, added in November, is on `StatusCheckFailed`: maximum above 0 for 3 consecutive minutes. CPU says how loaded the server is; the status check says whether it's alive at all, failing when the operating system stops answering or the host underneath it has a hardware, power or network fault. EC2 publishes it every minute at no charge whether or not detailed monitoring is on, so its period is always 60 seconds.

`evidence/cloudwatch-alarm.json` records both prod alarms: `CPUUtilization`, `Average > 60`, 60 s x 3, state `OK` since 23:58:23 UTC, about a minute and a half after the apply; and `StatusCheckFailed`, `Maximum > 0`, 60 s x 3, `OK` since 00:03:46, once the instance's first status checks had finished. `evidence/cloudwatch-alarm.png` shows the CloudWatch alarm list with all six alarms, two per environment, in `OK`.

## Task 8 - Recommendation

> **Question:** For a team fully committed to AWS with no multi-cloud plans, would you recommend this GitHub Actions pipeline or an AWS-native pipeline? Justify with at least three concrete factors.

**I would recommend an AWS-native pipeline** - CodePipeline orchestrating CodeBuild jobs that run Terraform, with a manual approval action in front of production - while keeping the code itself on GitHub through an AWS CodeConnections connection.

**1. Where the identity lives.** In this assignment the hardest part was not Terraform; it was getting AWS credentials to a machine that lives outside AWS. Every session I copied credentials into GitHub, scoped them to environments, deleted the repository copies and wrote an OIDC policy to describe what should have replaced all of that. CodeBuild runs as an IAM service role inside the account, so there is no key to store or rotate and no external identity provider to trust: each stage gets its own role with exactly the permissions it needs, and IAM is already the tool the team uses for everything else.

**2. What breaks the day you need VPC-internal access.** GitHub-hosted runners can only reach what is public. To smoke-test my pages I had to open port 80 to the internet. The day the team's application needs a private database, an internal load balancer or a VPC endpoint, a GitHub-hosted runner cannot reach it, and the only answer is a self-hosted runner fleet the team must build, secure and patch. CodeBuild can run inside the VPC's private subnets with security groups like any other workload.

**3. What the runner costs and who patches it.** CodeBuild bills per build-minute on the same AWS bill and budget as everything else, and AWS maintains and patches its managed build images. GitHub-hosted minutes are free for public repositories but billed for private ones, and self-hosted runners turn the team into the owners of a fleet. A team already committed to AWS gains nothing from a second vendor's billing and runner model.

**4. One audit trail.** When the Academy stopped my instances, CloudTrail answered "who and when" in minutes - but my approval record was in GitHub and the deployment record was in AWS, two places to reconcile. In CodePipeline the approval is an IAM-controlled action (`codepipeline:PutApprovalResult`), recorded in CloudTrail next to the deployment it released, and pipeline events flow to CloudWatch and EventBridge like every other AWS service.

**5. What the team already knows.** A team fully committed to AWS already works in IAM, CloudWatch, CloudTrail and the AWS CLI every day. An AWS-native pipeline is built from those same pieces: its permissions are IAM policies they already write, its build logs land in CloudWatch where they already look, and its approvals appear in CloudTrail where they already audit. A GitHub Actions pipeline asks the same people to learn and maintain a second permission model (repository, environment and organisation settings), a second secrets store and a second place to read logs, only to deploy into the cloud they already know. In this assignment that second model was most of the work: environments, branch policies, environment-scoped secrets and the refresh command that changes halfway through. Learning CodePipeline and CodeBuild is a one-time cost on top of skills the team already has; running GitHub Actions well is an ongoing cost of keeping two platforms' worth of knowledge current.

**What the team gives up.** GitHub's pull-request experience, its large marketplace of ready-made actions and fast credential-free checks like my LocalStack job (CodeBuild can run the same container, with more setup), and a less polished pipeline interface. Familiarity also cuts the other way for developers: most of them already know GitHub's pull requests and Actions syntax better than CodePipeline, so the first few weeks would be slower while they learn it. Portability is the usual argument for GitHub Actions, but a team with no multi-cloud plans would be paying for an option it has decided not to use.

**Verdict:** for this team, AWS-native. The deciding factor is identity: an AWS-native pipeline removes the credential-bridging problem this assignment spent most of its effort working around, instead of managing it better.

## Task 9 - Teardown

`scripts/teardown.sh` destroyed dev, staging and prod from the workstation into one file, `evidence/destroy-complete.txt` - `Destroy complete! Resources: 13 destroyed` for each - then deleted the three SSM parameters (afterwards, because the destroys still read them), and ended with proof that nothing is left: no instance, VPC or alarm tagged or named for the assignment, no parameters under `/acs730/assign1/`. The three state keys remain in the bucket as empty states, as the record of what existed. `cleanup-check.sh` reported nothing unexpected, so nothing is left running against the budget.

## Conclusion

The module, the three environments and the gate all worked as designed, but the most useful lessons came from where reality differed from the design.

The first is that a human gate is only as good as what the human can see when they approve. GitHub asks for approval before the prod job starts, so the plan inside that job is not visible yet. In October I read the prod plan from the workstation against the same state before each approval, and recorded that in the approval comment; in November I relied on staging having just applied the same commit, which is weaker, because prod has its own state. In a team I would make that structural: a plan-only job whose output is attached to the run, and an apply job that applies exactly that saved plan after approval.

The second is that infrastructure can be changed by things outside your code. The Academy stopped every instance in the middle of a deployment. What made it a 40-minute detour rather than a lost evening was that everything was reproducible: CloudTrail identified the caller, the state files said exactly what existed, and recovery was a destroy and a re-run through the same pipeline and the same gate, with a new approval. Idempotent scripts and per-environment state are what make that kind of recovery routine.

The third is that every substitute has an edge. LocalStack proved the module was coherent but could not emulate `MonitorInstances`, and refused a root volume without a size; environment-scoped secrets imitate an OIDC `sub` condition but are still copies of credentials that someone handles every session. In both cases the honest position is to use the substitute, know exactly what it does not prove, and say so - which is also why my recommendation for an AWS-only team is the pipeline that removes the credential problem rather than the one that manages it well.

The fourth came from the November re-run: a check that isn't required is advice, not a gate. PR #47 merged with its LocalStack check red because only Lab 4's `summary` and the tfsec scan are required, and only reading the check list before approving prod stopped a deployment from a failed commit. If this were a team repository, `assign1-ci` would be a required check too.
