# Final Project - Two Services, Terraform, Ansible and Kubernetes, Deployed on Merge

This folder deploys a two-service application. The backend is Apache on an EC2 VM, provisioned with my Assignment 1 Terraform module and configured with my Assignment 2 Ansible role. The frontend is my Week 4 Flask app, extended to call the backend, running on the Lab 7 kind cluster. One GitHub Actions run, started by merging a pull request into `main`, applies the Terraform, converges the VM, then builds and rolls out the frontend through the self-hosted runner. Two CloudWatch alarms watch the VM, and a required tfsec check blocks any change that opens it up further. The graded write-up (architecture, the design decision I defend, the credential choice, monitoring, the security gate, what I'd change and a course retrospective) is in **[REPORT.md](REPORT.md)**. This README covers the layout, every file and script, and how to run them.

## Layout

| Path | What it is |
|---|---|
| `REPORT.md` | The report |
| `terraform/staging/` | The environment the pipeline applies: a caller of `assignment1/terraform/modules/web-env` |
| `terraform/prod/` | The same caller with prod's values (state key, network, alarm threshold). Validated and scanned, never applied |
| `ansible/` | Configuration, dynamic inventory, group variables and a thin play that uses the Assignment 2 role in place |
| `app/` | The frontend: a copy of `lab4/` whose `/` calls the backend |
| `k8s/` | Namespace, deployer RBAC, Deployment and Service for the frontend |
| `scripts/` | Workstation scripts (table below) |
| `evidence/` | Evidence files (table below) |
| `../.github/workflows/final-ci.yml` | Pull request checks, GitHub-hosted, no AWS |
| `../.github/workflows/final-deploy.yml` | The merge-to-main deploy |
| `../.github/workflows/lab8-policy.yml` | The required security gate: tfsec over `lab8/` and over `final-project/terraform` |

## Where it came from

Nothing from earlier work was copied and edited in place. `terraform/*/main.tf` calls the Assignment 1 module by relative path (`source = "../../../assignment1/terraform/modules/web-env"`), and `ansible/ansible.cfg` points `roles_path` at `../../assignment2/ansible/roles`, so the final project runs the same files those assignments run. The app in `app/` started as a copy of `lab4/` (same Dockerfile, dependencies and `/healthz`); only `app.py` and its tests are new. The Kubernetes pieces follow my Lab 7 pattern, in their own namespace, on the cluster Lab 7 created.

The module itself changed once, in November, and the change was made in `assignment1/` (PRs #47 and #48), not here: an encrypted root volume, one `aws_security_group_rule` per rule so tfsec suppressions cover only the rules I accept, and a second alarm on `StatusCheckFailed`. The final project picked those up through the `source` line without a single edit to its callers' arguments.

## Terraform (`terraform/staging/`, `terraform/prod/`)

| Creates / changes | Deletes | Notes |
|---|---|---|
| Through the module, 13 resources: a VPC (`10.40.0.0/16` staging), two public subnets, an internet gateway, a route table and its two associations, a security group with two separate rules (`http_public`: port 80 from anywhere; `all_out`: all outbound) and no port 22, a `t3.micro` VM `acs730-assign1-staging-web` with `LabInstanceProfile`, IMDSv2 and an encrypted 8 GB root volume, and two alarms: `acs730-assign1-staging-cpu-alarm` (average CPU above 70%) and `acs730-assign1-staging-status-alarm` (any failed EC2 status check), each over 3 periods of 60 s | All of it, through `terraform destroy` (run by `scripts/teardown.sh`) | State in `acs730-tfstate-<account>`, key `final-project/staging/terraform.tfstate`. Tags from the caller's `default_tags`: `Project=final` and `Role=web` (the inventory selects by these). Outputs: `environment`, `instance_id`, `web_url`, `cpu_alarm_name`, `status_alarm_name`, `db_password_parameter_version`. The resource names keep the module's fixed `acs730-assign1-<environment>` prefix |
| `prod/`: the same, with key `final-project/prod/terraform.tfstate`, `10.50.0.0/16`, a 60% CPU alarm and its own parameter name | Nothing; never applied | Kept to show the multi-environment pattern. `final-ci` validates it and the required tfsec check scans it on every pull request |

Each folder has the same four files as Assignment 1's environments (`versions.tf`, `providers.tf`, `main.tf`, `outputs.tf`) plus its `.terraform.lock.hcl`.

## Ansible (`ansible/`)

| File | Purpose |
|---|---|
| `ansible.cfg` | Points at the dynamic inventory and at `../../assignment2/ansible/roles`; enables the `amazon.aws.aws_ec2` plugin |
| `inventory/final.aws_ec2.yml` | Running instances tagged `Role=web` and `Project=final`; group `role_web` from the `Role` tag; hosts named by instance ID. No host list, IDs or IPs |
| `group_vars/role_web.yml` | SSM connection (`community.aws.aws_ssm`), region and transfer bucket `acs730-final-ssm-<account>` |
| `site.yml` | Applies the Assignment 2 `webserver` role to `role_web` with `become`. Its two play variables (`webserver_title`, `webserver_message`) replace the role's defaults for the page text; everything else is the role's own |

## The frontend (`app/`)

| File | What it is |
|---|---|
| `app.py` | Flask. `/` calls `BACKEND_URL` with a 3-second timeout and returns `HTTP <status> from the VM: <the VM page's h1>`; if the call fails it returns **502** with the error, and with no `BACKEND_URL` it returns 500. The VM's address is never printed. `/healthz` checks only this process |
| `tests/test_app.py` | Four tests with the backend call faked (no network): `/healthz`, the backend's answer passed through, 502 when the backend refuses, 500 with no `BACKEND_URL` |
| `Dockerfile`, `.dockerignore`, `requirements.txt`, `requirements-dev.txt`, `pytest.ini` | Copied unchanged from `lab4/`: `python:3.12-slim-bookworm`, non-root `appuser` (uid 10001), gunicorn on port 8000 |

## Kubernetes (`k8s/`)

| File | What it is |
|---|---|
| `namespace.yaml` | Namespace `acs730-final` |
| `rbac.yaml` | ServiceAccount `acs730-final-deployer`, Role `acs730-final-deployer-role` (`get`, `list`, `watch`, `patch` on Deployments; `get`, `patch` on ConfigMaps and Services; nothing on Secrets, Pods or RBAC; this namespace only) and RoleBinding `acs730-final-deployer-binding`. Applied once by a person; the pipeline never applies it |
| `deployment.yaml` | `acs730-final-web`, 2 replicas, image `acs730-final-web:bootstrap` (the pipeline sets the real tag), environment from ConfigMap `acs730-final-config`, readiness and liveness on `/healthz`, requests and limits, non-root |
| `service.yaml` | `acs730-final-svc`, NodePort 30080: the one port `lab7/kind-cluster.yaml` maps to `127.0.0.1` on the workstation |

There's no `configmap.yaml`. The ConfigMap holds the VM's address, which changes whenever Terraform rebuilds the VM and must not be committed, so it's generated from the Terraform output: once by `scripts/bootstrap-k8s.sh`, then on every deploy by the pipeline.

## Scripts (`scripts/`)

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `configure-environment.sh` | GitHub Environment `final`: no reviewer, no wait timer, deployment branch policy `main` only | Nothing | `<owner>/<repo>` | Workstation, once |
| `create-ssm-parameter.sh` | SecureString `/acs730/assign1/final-<env>/db_password` (placeholder value) for each environment given; an existing one is kept | Nothing | `staging` and/or `prod` | Workstation, before the first plan of that environment |
| `create-ssm-bucket.sh` | Bucket `acs730-final-ssm-<account>` with all public access blocked | Nothing | None | Workstation, before the first Ansible run |
| `wait-for-ssm.sh` | Nothing | Nothing | Optional instance IDs; default = every running `Role=web`, `Project=final` instance | Workstation and the pipeline |
| `bootstrap-k8s.sh` | Namespace, RBAC, image `acs730-final-web:bootstrap` loaded into kind, the generated ConfigMap, the Deployment and the Service | Lab 7's Service `acs730-lab7-svc` (to free NodePort 30080); scales Lab 7's Deployment to 0 | None | Workstation, as ec2-user with the admin context, once |
| `make-deployer-kubeconfig.sh` | `/home/acs730-lab7-runner/.kube/config` logging in as `acs730-final-deployer` with a short-lived token (copy of Lab 7's script with the namespace and ServiceAccount changed) | Its temporary folder | Optional duration, default `24h` | Workstation, as ec2-user, each session the runner is used |
| `capture-evidence.sh` | `evidence/pipeline-merge-deploy.txt`, `credential-model.txt`, `kubectl-get-all.txt`, `app-response.txt` and `monitoring.txt`, all from one run, with the VM's IP masked. `monitoring.txt` waits up to 20 minutes for both alarms to leave `INSUFFICIENT_DATA`, then records their state, the last 15 minutes of both metrics and the frontend's HTTP code | Nothing (overwrites those five) | `<run-id> <pr-number>` | Workstation, straight after the merge-triggered run is green |
| `teardown.sh` | `evidence/teardown.txt` | Namespace `acs730-final`; the runner's service and registration (through `lab7/scripts/teardown-runner.sh`); the staging stack (`terraform destroy`: VM, VPC, subnets, gateway, routes, security group and rules, both alarms); the SSM parameter; the transfer bucket; the frontend images on the workstation. Puts Lab 7's Service back and scales it to 2. Ends with proof that nothing is left | None | Workstation, at the end |
| `../../scripts/refresh-gha-creds.sh` (course template) | The three AWS secrets on each environment named, and the `AWS_REGION` variable | Nothing | `jhui26-seneca/acs730-coursework final` (add `staging prod assign2` when those are needed too) | Workstation, once per lab session |

## Workflows (repository root)

| Workflow | Runs on | Trigger | What it does |
|---|---|---|---|
| `final-ci.yml` | `ubuntu-24.04` | Pull requests touching `final-project/**` or either final workflow | `terraform fmt -check` and `validate` of both callers (no backend), Ansible `--syntax-check` of the play against the Assignment 2 role, `kubeconform -strict` of `k8s/`, and the app's tests and flake8. No AWS credentials, nothing deployed. Not a required check |
| `final-deploy.yml` | `infra` and `configure`: `ubuntu-24.04` in Environment `final`. `deploy`: `[self-hosted, acs730-lab7]` | Push to `main` touching `final-project/terraform`, `ansible`, `app`, `k8s`, `scripts/wait-for-ssm.sh` or the workflow. No `pull_request`, no `workflow_dispatch` | `infra`: shows its AWS identity (session name masked), `terraform apply` of staging, passes `web_url` on. `configure`: waits for SSM, converges with the role, runs it again and fails on any `changed` or `failed`. `deploy`: proves it has no AWS credentials, shows its cluster identity, builds the image tagged with the commit SHA, `kind load`s it, then (paused) generates the ConfigMap, applies the Deployment and Service and sets the image, resumes, waits on `rollout status --timeout=120s`, and smoke-tests that `/` returns 200 with the VM's answer |
| `lab8-policy.yml` (from Lab 8) | `ubuntu-latest` | Every pull request and every push to `main`, with no `paths:` filter | Job `tfsec (HIGH and above)`, a required status check on `main`: tfsec v1.28.14 over `lab8/`, then over `final-project/terraform`, which follows both callers into the Assignment 1 module. Any HIGH or CRITICAL finding fails the job and blocks the merge |

`final-ci` and `final-deploy` use `contents: read`; `final-deploy` has concurrency group `final-deploy`, never cancelled mid-run. The required check has no `paths:` filter on purpose: a required check must report on every pull request, or pull requests that don't touch these folders would wait for it forever.

## Evidence

All of it comes from the re-run on 13 November 2026 (Toronto time; the UTC timestamps in the files read 14 November).

| File | Shows |
|---|---|
| `evidence/caller-identity.png` | The workstation's AWS identity (`assumed-role/LabRole`) in that session, account ID masked. The same screenshot as Assignment 1's, because both ran in the same session |
| `evidence/terraform-apply.txt` | The `source` line pointing at the Assignment 1 module, `terraform init`, and the staging apply: `Apply complete! Resources: 13 added` |
| `evidence/config-layer.txt` | The page before (the module's user_data), run 1 (`changed=3`), run 2 (`changed=0 failed=0`), and the page after (the role's template) |
| `evidence/pipeline-merge-deploy.txt` | PR #52, its merge commit `fa8ef4066fdb`, and run 43542051425 started by it (`event: push`, `main`, same SHA): the job summary and the full log of all three jobs |
| `evidence/credential-model.txt` | Where the AWS secrets live (Environment `final` only), its rules (no reviewer, `main` only), the identity each job used in that run, how long the AWS and Kubernetes credentials live, gitleaks over all history (exit 0), and the OIDC design for a real account |
| `evidence/kubectl-get-all.txt` | After that run: Deployment 2/2 on `acs730-final-web:fa8ef4066fdb` (the merge commit), the Pods, Service, endpoints and rollout history |
| `evidence/app-response.txt` | The frontend through the NodePort: `HTTP/1.1 200 OK` and `backend: HTTP 200 from the VM: ACS730 final project - backend`, `/healthz`, the VM called directly, and the ConfigMap that links them |
| `evidence/monitoring.txt` | Straight after that run: both alarms `OK`, the last 15 minutes of `CPUUtilization` and `StatusCheckFailed` for the VM, and the frontend answering `HTTP 200` at the same moment |
| `evidence/security-gate-blocked.txt` | PR #51, which opened port 8080 to the internet in the staging caller: `mergeStateStatus BLOCKED`, the one-line diff, every check (all pass except `tfsec (HIGH and above)`), and the CRITICAL finding on `extra_ingress` |
| `evidence/security-gate-blocked.png` | The same pull request on GitHub: the failed required check and merging blocked |
| `evidence/tfsec-scan.txt` | tfsec v1.28.14 three ways: the gate exactly as the required check runs it (`No problems detected`, exit 0), then each caller at every severity (6 passed, 4 ignored, 1 MEDIUM finding each) |
| `evidence/teardown.txt` | Namespace deleted, runner deregistered, `Destroy complete! Resources: 13 destroyed`, parameter and bucket deleted, every proof line empty, Lab 7 answering on NodePort 30080 again |

The VM's public IP is replaced by `<vm-public-ip>` in every file.

## Run order

1. Each session: Start Lab, resize the workstation to t3.large if needed, `./scripts/session-start.sh`, then `./scripts/refresh-gha-creds.sh jhui26-seneca/acs730-coursework final`. Start the kind node if it's stopped (`docker start acs730-lab7-control-plane`).
2. Once: `scripts/configure-environment.sh jhui26-seneca/acs730-coursework`, `scripts/create-ssm-parameter.sh staging`, `scripts/create-ssm-bucket.sh`.
3. `terraform -chdir=terraform/staging init`, `plan`, `apply`; then from `ansible/`: `ansible-inventory --graph` and `ansible-playbook site.yml` twice.
4. `scripts/bootstrap-k8s.sh`, then the runner: `scripts/make-deployer-kubeconfig.sh`, the iptables rule that blocks the runner user from the metadata service, registration and `svc.sh install` (the commands in the Lab 7 guide's appendix).
5. Open a pull request (`final-ci`, `summary` and `tfsec (HIGH and above)` must pass), merge it, watch `final-deploy`, then `scripts/capture-evidence.sh <run-id> <pr-number>`.
6. `scripts/teardown.sh`, then `../scripts/cleanup-check.sh`. Merge evidence and documentation with `[skip ci]` in the merge subject.
