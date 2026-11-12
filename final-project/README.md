# Final Project - Two Services, Terraform, Ansible and Kubernetes, Deployed on Merge

This folder deploys a two-service application. The backend is Apache on an EC2 VM, provisioned with my Assignment 1 Terraform module and configured with my Assignment 2 Ansible role. The frontend is my Week 4 Flask app, extended to call the backend, running on the Lab 7 kind cluster. One GitHub Actions run, started by merging a pull request into `main`, applies the Terraform, converges the VM, then builds and rolls out the frontend through the self-hosted runner. The graded write-up (the VM-versus-container rationale, each requirement, the credential model and what I'd change in a real account) is in **[REPORT.md](REPORT.md)**. This README covers the layout, every file and script, and how to run them.

## Layout

| Path | What it is |
|---|---|
| `REPORT.md` | The report |
| `terraform/staging/` | The environment the pipeline applies: a caller of `assignment1/terraform/modules/web-env` |
| `terraform/prod/` | The same caller with prod's values (state key, network, alarm threshold). Validated, never applied |
| `ansible/` | Configuration, dynamic inventory, group variables and a thin play that uses the Assignment 2 role in place |
| `app/` | The frontend: a copy of `lab4/` whose `/` calls the backend |
| `k8s/` | Namespace, deployer RBAC, Deployment and Service for the frontend |
| `scripts/` | Workstation scripts (table below) |
| `evidence/` | Evidence files (table below) |
| `../.github/workflows/final-ci.yml` | Pull request checks, GitHub-hosted, no AWS |
| `../.github/workflows/final-deploy.yml` | The merge-to-main deploy |

## Where it came from

Nothing from earlier work was copied and edited in place. `terraform/*/main.tf` calls the Assignment 1 module by relative path (`source = "../../../assignment1/terraform/modules/web-env"`), and `ansible/ansible.cfg` points `roles_path` at `../../assignment2/ansible/roles`, so `assignment1/`, `assignment2/` and `lab4/` are unchanged. The app in `app/` started as a copy of `lab4/` (same Dockerfile, dependencies and `/healthz`); only `app.py` and its tests are new. The Kubernetes pieces follow my Lab 7 pattern, in their own namespace, on the cluster Lab 7 created.

## Terraform (`terraform/staging/`, `terraform/prod/`)

| Creates / changes | Deletes | Notes |
|---|---|---|
| Through the module: a VPC (`10.40.0.0/16` staging), two public subnets, an internet gateway and route table, a security group with HTTP from anywhere and no port 22, a `t3.micro` VM `acs730-assign1-staging-web` with `LabInstanceProfile` and IMDSv2, and the CPU alarm `acs730-assign1-staging-cpu-alarm` (70%, 1-minute metrics) | All of it, through `terraform destroy` (run by `scripts/teardown.sh`) | State in `acs730-tfstate-<account>`, key `final-project/staging/terraform.tfstate`. Tags from the caller's `default_tags`: `Project=final` and `Role=web` (the inventory selects by these). Outputs: `environment`, `instance_id`, `web_url`, `cpu_alarm_name`, `db_password_parameter_version`. The resource names keep the module's fixed `acs730-assign1-<environment>` prefix |
| `prod/`: the same, with key `final-project/prod/terraform.tfstate`, `10.50.0.0/16`, a 60% alarm and its own parameter name | Nothing; never applied | Kept to show the multi-environment pattern. `final-ci` validates it on every pull request |

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
| `capture-evidence.sh` | `evidence/pipeline-merge-deploy.txt`, `credential-model.txt`, `kubectl-get-all.txt`, `app-response.txt`, all from one run, with the VM's IP masked | Nothing (overwrites those four) | `<run-id> <pr-number>` | Workstation, straight after the merge-triggered run is green |
| `teardown.sh` | `evidence/teardown.txt` | Namespace `acs730-final`; the runner's service and registration (through `lab7/scripts/teardown-runner.sh`); the staging stack (`terraform destroy`); the SSM parameter; the transfer bucket; the frontend images on the workstation. Puts Lab 7's Service back and scales it to 2. Ends with proof that nothing is left | None | Workstation, at the end |
| `../../scripts/refresh-gha-creds.sh` (course template) | The three AWS secrets on each environment named, and the `AWS_REGION` variable | Nothing | `jhui26-seneca/acs730-coursework final` (add `staging prod assign2` when those are needed too) | Workstation, once per lab session |

## Workflows (repository root)

| Workflow | Runs on | Trigger | What it does |
|---|---|---|---|
| `final-ci.yml` | `ubuntu-24.04` | Pull requests touching `final-project/**` or either final workflow | `terraform fmt -check` and `validate` of both callers (no backend), Ansible `--syntax-check` of the play against the Assignment 2 role, `kubeconform -strict` of `k8s/`, and the app's tests and flake8. No AWS credentials, nothing deployed. Not a required check |
| `final-deploy.yml` | `infra` and `configure`: `ubuntu-24.04` in Environment `final`. `deploy`: `[self-hosted, acs730-lab7]` | Push to `main` touching `final-project/terraform`, `ansible`, `app`, `k8s`, `scripts/wait-for-ssm.sh` or the workflow. No `pull_request`, no `workflow_dispatch` | `infra`: shows its AWS identity (session name masked), `terraform apply` of staging, passes `web_url` on. `configure`: waits for SSM, converges with the role, runs it again and fails on any `changed` or `failed`. `deploy`: proves it has no AWS credentials, shows its cluster identity, builds the image tagged with the commit SHA, `kind load`s it, then (paused) generates the ConfigMap, applies the Deployment and Service and sets the image, resumes, waits on `rollout status --timeout=120s`, and smoke-tests that `/` returns 200 with the VM's answer |

Both use `contents: read`; `final-deploy` has concurrency group `final-deploy`, never cancelled mid-run.

## Evidence

| File | Shows |
|---|---|
| `evidence/caller-identity.png` | The workstation's AWS identity (`assumed-role/LabRole`) |
| `evidence/terraform-apply.txt` | The `source` line pointing at the Assignment 1 module, `terraform init`, and the staging apply: `Apply complete! Resources: 10 added` |
| `evidence/config-layer.txt` | The page before (the module's user_data), run 1 (`changed=3`), run 2 (`changed=0 failed=0`), and the page after (the role's template) |
| `evidence/pipeline-merge-deploy.txt` | PR #45, its merge commit, and run 43277666062 started by it (`event: push`, `main`, same SHA): the job summary and the full log of all three jobs |
| `evidence/credential-model.txt` | Where the AWS secrets live (Environment `final` only), its rules (no reviewer, `main` only), the identity each job used in that run, how long the AWS and Kubernetes credentials live, gitleaks over all history (exit 0), and the OIDC design for a real account |
| `evidence/kubectl-get-all.txt` | After that run: Deployment 2/2 on `acs730-final-web:8d368586b551` (the merge commit), the Pods, Service, endpoints and rollout history |
| `evidence/app-response.txt` | The frontend through the NodePort: `HTTP/1.1 200 OK` and `backend: HTTP 200 from the VM: ACS730 final project - backend`, `/healthz`, the VM called directly, and the ConfigMap that links them |
| `evidence/tfsec-scan.txt` | tfsec v1.28.14 over both callers (and through them the Assignment 1 module): 6 passed, 7 findings each, discussed under "Security review" in REPORT.md. The required gate scans `lab8/` only |
| `evidence/teardown.txt` | Namespace deleted, runner deregistered, `Destroy complete! Resources: 10 destroyed`, parameter and bucket deleted, every proof line empty |

The VM's public IP is replaced by `<vm-public-ip>` in every file.

## Run order

1. Each session: Start Lab, resize the workstation to t3.large if needed, `./scripts/session-start.sh`, then `./scripts/refresh-gha-creds.sh jhui26-seneca/acs730-coursework final`. Start the kind node if it's stopped (`docker start acs730-lab7-control-plane`).
2. Once: `scripts/configure-environment.sh jhui26-seneca/acs730-coursework`, `scripts/create-ssm-parameter.sh staging`, `scripts/create-ssm-bucket.sh`.
3. `terraform -chdir=terraform/staging init`, `plan`, `apply`; then from `ansible/`: `ansible-inventory --graph` and `ansible-playbook site.yml` twice.
4. `scripts/bootstrap-k8s.sh`, then the runner: `scripts/make-deployer-kubeconfig.sh`, the iptables rule that blocks the runner user from the metadata service, registration and `svc.sh install` (the commands in the Lab 7 guide's appendix).
5. Open a pull request (`final-ci`, `summary` and `tfsec` must pass), merge it, watch `final-deploy`, then `scripts/capture-evidence.sh <run-id> <pr-number>`.
6. `scripts/teardown.sh`, then `../scripts/cleanup-check.sh`. Merge evidence and documentation with `[skip ci]` in the merge subject.
