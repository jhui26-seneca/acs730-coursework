# Final Project - Two Services, Terraform, Ansible and Kubernetes, Deployed on Merge

**Report** - John Hui (GitHub `jhui26-seneca`), ACS730, November 2026. Repository: `jhui26-seneca/acs730-coursework`, folder `final-project/`. File-by-file details and scripts are in `README.md`; every claim below points to a file in `evidence/`.

## Introduction

The brief asks for four things at once: Terraform that reuses my Assignment 1 module and its multi-environment pattern, a configuration layer for whatever runs on a VM, Kubernetes deployed through the Week 9 and 10 self-hosted-runner pipeline for whatever is containerised, and a deploy that happens on every merge to `main` with no long-lived AWS credentials. Together they mean the application needs at least one piece on a VM and one in a container, and one has to depend on the other.

So the application is deliberately small. The backend is Apache on an EC2 VM, built by the Assignment 1 module and configured by the Assignment 2 role. The frontend is my Week 4 Flask app with one change: its home page calls the backend and quotes the answer. Everything else in the folder exists to build, connect and prove those two pieces.

The work was delivered in three pull requests. #44 added the Terraform callers, the Ansible play, the frontend, the manifests and both workflows. #45 fixed the deploy workflow after its first run (more on that below), and its merge produced run `43277666062`, the deployment all the evidence describes. #46 added this report, the README and the remaining evidence. Like everything this term, it ran in an AWS Academy Learner Lab, where IAM writes are denied and the budget is fixed. Both constraints come up again below.

## 1. What runs where, and why

**The frontend runs in a container on Kubernetes because it's stateless and it's the piece that changes.** It holds no data and no session, so any Pod can answer any request, and Kubernetes can replace, scale and roll it back without anyone noticing. It's also what a developer changes most often, and a rolling update with a readiness gate is the safest way I've seen this term to ship frequent changes: Lab 7's bad deploy never took the site down.

**The backend runs on a VM because it's the long-lived piece, and it's managed like a server.** Apache here stands in for the kind of dependency teams usually keep on VMs: a database, a legacy service, anything with its own operating system, packages and configuration files that someone has to patch and keep from drifting. That's exactly what Assignment 2's role was built for. It converges the server to a known state and proves it with `changed=0` on the next run. A Pod is the wrong shape for that, because it's meant to be thrown away and replaced, not converged.

The dependency runs one way: the frontend calls the backend. The Flask app reads `BACKEND_URL`, fetches the VM's page with a 3-second timeout, and returns `HTTP 200 from the VM: <the page's title>`. If the VM doesn't answer, `/` returns **502** with the error rather than a polite 200. A frontend that hides a broken dependency would make the integration look healthy when it isn't. `/healthz` checks only the Flask process, so a VM outage makes `/` fail loudly without Kubernetes pulling every Pod out of the Service.

## 2. Terraform: the Assignment 1 module, reused

`terraform/staging/main.tf` and `terraform/prod/main.tf` each call the module with one line: `source = "../../../assignment1/terraform/modules/web-env"`. `evidence/terraform-apply.txt` starts with that line, then the `init` and the apply: `Apply complete! Resources: 10 added`. That's a VPC, two public subnets, an internet gateway and route table, the HTTP-only security group, the VM and the CPU alarm, the same ten resources each Assignment 1 environment had.

The multi-environment pattern is unchanged: one module and one folder per environment, each with its own state key in the shared bucket. The callers differ only in what genuinely differs:

| | staging (applied) | prod (validated only) |
|---|---|---|
| State key | `final-project/staging/terraform.tfstate` | `final-project/prod/terraform.tfstate` |
| VPC | `10.40.0.0/16` | `10.50.0.0/16` |
| CPU alarm threshold | 70% | 60% |
| SSM parameter | `/acs730/assign1/final-staging/db_password` | `/acs730/assign1/final-prod/db_password` |

Only staging is applied: the budget doesn't stretch to two VMs, and nothing requires both. `final-ci` validates prod on every pull request, so it can't quietly rot. I picked new network ranges rather than Assignment 1's, so the two projects could never collide.

Reusing a module unchanged had two costs, and I hit both. The module builds its resource names from a fixed `acs730-assign1-<environment>` prefix, so the VM is called `acs730-assign1-staging-web`. The caller's `default_tags` (`Project=final`, `Role=web`) are what tell these resources apart, and they're what the Ansible inventory selects by. Second, my own validation rule from Assignment 1 rejected my first parameter name: `db_password_parameter_name must start with /acs730/assign1/`. Terraform stopped at plan time, before creating anything, and the fix was to use a name inside that prefix. Both are reasons a reusable module should take its naming as inputs. I left `assignment1/` exactly as submitted rather than change a module that's already been handed in, and I'd add a `name_prefix` variable the next time I wrote one.

I applied staging from the workstation first, then let the pipeline own it. In the merge-triggered run, `infra` read the same state and printed `No changes. Your infrastructure matches the configuration.` (`evidence/pipeline-merge-deploy.txt`), so the pipeline and the workstation agree on one state file.

## 3. The configuration layer: the Assignment 2 role, in place

The role isn't copied. `ansible/ansible.cfg` sets `roles_path = ../../assignment2/ansible/roles`, so the play runs the same files Assignment 2 ran. The final project adds only its own inventory (running instances tagged `Role=web` and `Project=final`), its own SSM transfer bucket, and two play variables that change the page's title and message. Ansible reaches the VM over Systems Manager with no SSH key and no port 22.

`evidence/config-layer.txt` shows the whole change. Before Ansible, the page was the module's user_data output, `ACS730 assign1 - staging`. Run 1 reported `ok=6 changed=3`: the Apache settings file and the page were rewritten, and the settings change triggered the restart handler. httpd was already installed and running from user_data, so those two tasks were `ok`. Run 2, with nothing edited in between, reported `ok=5 changed=0 failed=0`. The page then read `ACS730 final project - backend`, and the `Server:` header showed `Apache` with no version, which is the role's settings template at work. In the pipeline, `configure` runs the play twice on every deploy and fails the job if the second run changes anything.

I chose Ansible over a Packer golden AMI for one concrete reason. The Assignment 1 module installs httpd and writes its own `index.html` in user_data at first boot. A baked page would be overwritten the moment the VM started, while a converge runs after boot and wins. Packer would have meant editing the module to skip its user_data, which I'd ruled out. For a single long-lived server, converging is also the better fit anyway, as my Assignment 2 timings argued.

## 4. Kubernetes through the self-hosted runner pipeline

The cluster is the one-node kind cluster from Lab 7, still on the workstation. The final project has its own namespace, `acs730-final`, and its own deployment identity: ServiceAccount `acs730-final-deployer`, whose Role can `get`, `list`, `watch` and `patch` Deployments and `get` and `patch` ConfigMaps and Services in that namespace, and nothing else. The runner is Lab 7's, re-registered, running as its own Linux user, with a kubeconfig for that ServiceAccount and a 24-hour token. A person creates the objects once (`scripts/bootstrap-k8s.sh`), and the pipeline can only change them.

The `deploy` job follows Lab 7's shape:

1. It proves the job has no AWS credentials, then prints its cluster identity (`system:serviceaccount:acs730-final:acs730-final-deployer`).
2. It builds the frontend tagged with the first 12 characters of the commit SHA and `kind load`s it into the node.
3. With the Deployment paused, it generates the ConfigMap from the Terraform output, applies the Deployment and Service, and sets the new image. Then it resumes, so the whole change is one revision and `rollout undo` lands on the last good build.
4. `kubectl rollout status --timeout=120s` is the gate.
5. A smoke test requires `/` to return 200 **and** contain `HTTP 200 from the VM`. A frontend that's up but can't reach its backend fails the run.

The ConfigMap is generated rather than committed because it holds the VM's public address. That changes whenever Terraform rebuilds the VM, and IP addresses stay out of this repository. The address travels from the `infra` job's `web_url` output to the `deploy` job, which writes it into the ConfigMap on every run.

One constraint shaped this part. Lab 7's `kind-cluster.yaml` maps exactly one NodePort, 30080, to the workstation, and changing that means rebuilding the cluster. So `bootstrap-k8s.sh` removes Lab 7's Service and scales Lab 7's Deployment to 0, and `teardown.sh` puts both back. `teardown.txt` ends with Lab 7 answering on 30080 again.

`evidence/kubectl-get-all.txt` shows the result of run 43277666062: the node `Ready`, Deployment `2/2` on `acs730-final-web:8d368586b551` (the merge commit is `8d368586b551...`), two Pods, two endpoints behind the Service, and the bootstrap ReplicaSet scaled to 0 as revision 1.

## 5. Deployed on every merge to main, with no long-lived AWS credentials

**The trigger.** `final-deploy.yml` runs on `push` to `main` only, filtered to the folders that change what's deployed. It has no `pull_request` trigger, because a fork's code must never reach a runner on my workstation, and no `workflow_dispatch`, because the deploy has to come from a merge. On this repository a push to `main` is a merged pull request, because branch protection requires Lab 4's `summary` and Lab 8's `tfsec (HIGH and above)` checks. `evidence/pipeline-merge-deploy.txt` ties it together. PR #45 was merged at 18:13:55 UTC with merge commit `8d368586b551`. Run 43277666062 started three seconds later with `event: push`, `branch: main` and that same SHA. It finished green at 18:16:31: `infra` 23 s, `configure` 1 min 36 s, `deploy` 22 s. That's 2 minutes 36 seconds from merge to a verified rollout, with no manual step in any job.

**The credentials** (`evidence/credential-model.txt`):

- **Where they live.** The AWS secrets exist only on GitHub Environment `final`, and there are none at repository level. `final` has no required reviewer, because an approval would be a human step inside the merge run. It does have a deployment branch policy that allows only `main`.
- **Who uses them.** Only `infra` and `configure` declare that environment. Inside the run, both print `assumed-role/voclabs/<session>` (I mask the session name, which carries my Seneca login), and the action shows each key as `***`.
- **The job that touches the cluster has no AWS access at all.** `deploy` prints "No AWS credentials on the self-hosted runner". It would fail the job if it found any, because the runner's user is blocked from the instance metadata service by the iptables rule from Lab 7. Its only credential is the ServiceAccount token, valid from 17:59 to 17:59 UTC the next day.
- **How long they live.** The AWS credentials are Academy session credentials, pushed by `refresh-gha-creds.sh` at the start of the session and dead when the session ends.
- **Nothing long-lived in the repository.** gitleaks over every commit on every branch exits 0.

That's the accepted answer here: credentials that expire with the lab session, refreshed each session, never committed. In a real account I'd store no keys at all and use OIDC, with the trust policy from my Assignment 1 report scoped to `sub = repo:jhui26-seneca/acs730-coursework:environment:final`. Only a job running in this environment could then assume the role, and GitHub only starts such a job from `main`, so the branch policy becomes part of AWS's decision, not just GitHub's.

**The first run, and why it isn't the evidence.** Run 43276314354, from merging #44, went green in 8 seconds of `deploy`, and that was wrong. My first paste of `final-deploy.yml` had been cut off after the `kubectl apply` line. The run paused the Deployment, applied the manifests and stopped: no `set image`, no `resume`, no gate, no smoke test. Every step that did run succeeded, so the run was green, and the Deployment sat paused on the bootstrap image. I found it by reading the step list, not the colour. I resumed the Deployment by hand, restored the missing steps in PR #45, and captured all the evidence from that merge instead. The lesson is the one Lab 7 taught from the other side: a pipeline is only as good as its last check. A deploy with no gate looks exactly as green as one with a gate, so I now count the steps before I trust a run.

## 6. The two services, integrated

`evidence/app-response.txt` was captured in the same sitting as the Kubernetes evidence, after the pipeline's rollout. Through the NodePort, the frontend returns `HTTP/1.1 200 OK` with:

```
ACS730 final project frontend (Flask on Kubernetes) -- version 8d368586b551
backend: HTTP 200 from the VM: ACS730 final project - backend
```

The first line is the build the merge produced; the second is the VM's page title, quoted by the frontend. Calling the VM directly returns the same `<h1>ACS730 final project - backend</h1>`, and the frontend's ConfigMap shows where the address came from: `BACKEND_URL = http://<vm-public-ip>`, `APP_VERSION = 8d368586b551`, written by run 43277666062. The path is real network traffic: a Pod on the kind node, out through the workstation's public address, to the VM's public address on port 80.

The 502 behaviour is tested rather than assumed. `app/tests/test_app.py` fakes the backend call and checks all four cases: a normal answer, a refused connection (502), no `BACKEND_URL` (500), and `/healthz` staying independent. `final-ci` runs those tests on every pull request.

## 7. Questions I'd expect to be asked

**What happens if the pipeline runs twice?** Nothing changes, and that's checked. Terraform reads the same state and reports `No changes`. Ansible converges a server that's already right and must report `changed=0`, or the job fails. The new image is tagged with the commit SHA, so a re-run of the same commit sets the image it already runs and Kubernetes doesn't start a new rollout. The concurrency group queues a second merge behind the first, rather than running two applies at once or cancelling one halfway.

**What if a bad image merges, and how do you roll back?** The gate catches it before anyone has to. In Lab 7 I merged a deliberately broken readiness probe: `rollout status` timed out after 120 s, the run went red, and because Kubernetes doesn't remove an old Pod until a new one is Ready, the old Pods kept answering 200 throughout. This pipeline has the same gate plus a stronger smoke test. An image that starts but can't reach the VM also fails the run, because `/` returns 502. Rolling back is two steps. `kubectl rollout undo` puts the cluster back on the last good build straight away, and the pause makes that exactly one revision back. Then a revert on `main` fixes the source of truth, so the next merge doesn't redeploy the bad change.

**What does this cost to run for a day, and what did you turn off?** Roughly $2.65 a day while it's up, at us-east-1 on-demand prices:

| Item | Per day |
|---|---|
| Workstation, t3.large (the cluster and the runner) | $2.00 |
| Backend VM, t3.micro | $0.25 |
| Two public IPv4 addresses | $0.24 |
| EBS (20 GB workstation, 8 GB VM) | $0.07 |
| Detailed monitoring and the CPU alarm | $0.07 |

Three-quarters of that is the workstation. I turned everything off the same day: `teardown.sh` deleted the namespace, deregistered the runner, destroyed all ten Terraform resources, and deleted the SSM parameter and the transfer bucket (`evidence/teardown.txt`, every proof line empty, and `cleanup-check.sh` found nothing unexpected). Then the workstation was stopped. Left running all month it would be about $80, more than the whole $50 Academy budget, so in a real account I wouldn't run the cluster on a big always-on workstation at all.

**What would you do differently with a real AWS account?** The IAM-denied constraints shaped the identity half of this design, and almost none of the rest. With IAM I'd use OIDC with one role per environment and no stored keys. The runner wouldn't need an iptables rule to stop it borrowing an unscoped instance role; it would get no role at all, or a narrow one like the policy I wrote in Lab 8. The budget shaped the other half. I'd run the frontend on EKS or another managed cluster, with an ephemeral runner inside the VPC. The VM would sit in a private subnet that accepts port 80 only from the cluster's nodes, instead of from the internet. The image would be built once and pushed to ECR, not built on the runner and side-loaded into kind. And the module would take its name prefix and parameter path as inputs.

## 8. Security review

The required tfsec check scans `lab8/` only, so I ran tfsec v1.28.14 over both callers once by hand (`evidence/tfsec-scan.txt`). It follows the `source` line into the Assignment 1 module, so it's really a scan of that module with the final project's values. Each caller passed 6 checks and reported 7 findings, the same 7 for staging and prod:

| Finding | Severity | Where | My decision |
|---|---|---|---|
| `aws-ec2-no-public-ingress-sgr` (2 results) | CRITICAL | The security group's HTTP rule, port 80 from `0.0.0.0/0` | Accepted here, by design. The frontend runs on a kind cluster on my workstation, in a different VPC, so it reaches the VM over the internet. In a real account the VM would sit in a private subnet, with port 80 open only to the cluster nodes' security group |
| `aws-ec2-no-public-egress-sgr` | CRITICAL | All outbound traffic to `0.0.0.0/0` | Accepted with the reason I gave in Lab 8: the SSM agent, `dnf` and Ansible's S3 transfers need outbound HTTPS to addresses with no fixed range, and nothing on the internet can open a connection in through an outbound rule. First fix: narrow it to 443. Then VPC endpoints for SSM and S3 |
| `aws-ec2-enable-at-rest-encryption` | HIGH | The VM's root volume | A real gap, and the one I'd fix first. `root_block_device { encrypted = true }` costs nothing and worked in Lab 8 |
| `aws-ec2-no-public-ip-subnet` (2 results) | HIGH | Both subnets set `map_public_ip_on_launch = true` | Follows from the first row. The VM needs a public address to be reached from the workstation, and the module has no NAT gateway (about $33 a month) for private subnets to use. In a real account: private subnets, plus a NAT gateway or VPC endpoints |
| `aws-ec2-require-vpc-flow-logs-for-all-vpcs` | MEDIUM | The VPC | I'd turn flow logs on in a real account, to have something to investigate with. Here it would add CloudWatch Logs cost for traffic nobody reviews |

I didn't fix or suppress any of them in this project. All seven are in `assignment1/`, which stays as I submitted it, and a `tfsec:ignore` would have to go in that module too. Pointing the required gate at `final-project/` would also block every merge on findings I've already decided to accept. Recording each one with a reason, as in my Assignment 2 security review, is more honest than switching the gate off or hiding the findings. The fixes belong in the module itself: an encrypted root volume by default, and inputs for subnet type and egress, so the next caller can choose.

## Conclusion

The four requirements came together with very little new code. Terraform is my Assignment 1 module behind a two-line caller. The VM is configured by my Assignment 2 role without a single file copied. The deploy is my Lab 7 pipeline pointed at a new namespace. And the credentials are the session model I've used since Week 3, with the OIDC design from Assignment 1 as the real-world answer. The new parts are the glue: a backend address that flows from a Terraform output to a generated ConfigMap, a smoke test that checks the dependency and not just the frontend, and a deploy job that refuses to run if it can see AWS credentials.

The most useful lessons came from what went wrong. Reusing a module unchanged meant living with its naming and its validation, which is fine until it isn't. A NodePort mapping chosen in Lab 7 decided what the final project could do with Lab 7's own Service. And the run I first thought was the deployment had silently skipped its own gate. If I did this again, I'd write workflows as files and copy them across rather than paste long blocks into a terminal, and I'd add a check that fails a deploy workflow which doesn't contain its gate.
