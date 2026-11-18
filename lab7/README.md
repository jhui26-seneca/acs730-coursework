# Lab 7: Kubernetes fundamentals and CI/CD to Kubernetes

Week 9 runs my Week 4 Flask image on a one-node kind cluster on the workstation, using manifests in `lab7/k8s/`. Week 10 puts a pipeline in front of it: a self-hosted GitHub Actions runner on the same machine, a ServiceAccount scoped by RBAC, a deploy that checks its own rollout, a deliberately bad deploy that the check catches, and a rollback.

## Versions

| Tool | Version | How it was installed |
|---|---|---|
| kubectl | v1.31.1 | From `dl.k8s.io` with its `.sha256` checked. The lab first ran on v1.31.0 from `./scripts/install-lab-tools.sh lab8`; I moved to v1.31.1 on November 18 to match the version the walkthrough pins |
| kind | v0.24.0 | `./scripts/install-lab-tools.sh lab8` |
| Kubernetes (the kind node) | v1.31.0 | the default node image for kind v0.24.0 (`kubectl version` shows `Server Version: v1.31.0`) |
| kubeconform | v0.8.0 | GitHub release, checksum checked, in CI (`lab7-ci.yml`) and on the workstation. Moved from v0.6.7 on November 18, the walkthrough's pin |
| GitHub Actions runner | 2.338.2 | GitHub release, checksum taken from the release notes |

Why pin them: kubectl is only supported within one minor version of the API server, and a kind release ships a node image for one Kubernetes version, so an unpinned kubectl or kind drifts away from the cluster and starts printing skew warnings, then calling APIs the cluster doesn't have. The same goes for kubeconform: CI and the workstation run the same version, so they can't disagree about what `-strict` means. A v1.31.1 client against the v1.31.0 node is a patch-level difference, which is fine.

The workstation was resized to t3.large from CloudShell first. kind and the app together need more memory than a t3.micro has.

## What's in this folder

| File | What it is |
|---|---|
| `kind-cluster.yaml` | The cluster: one control-plane node named `acs730-lab7`, with NodePort 30080 mapped to `127.0.0.1:30080` on the workstation. It sits outside `k8s/` because it isn't a Kubernetes object, and `kubeconform -strict` fails on it |
| `k8s/namespace.yaml` | Namespace `acs730-lab7`. Applied on its own first, since `kubectl apply -f k8s/` goes alphabetically |
| `k8s/configmap.yaml` | `acs730-lab7-config`, sets `APP_VERSION=lab7`, which the app prints |
| `k8s/secret.yaml` | `acs730-lab7-secret`, a placeholder value only. The repo is public and a Secret is only base64-encoded, so nothing real goes here |
| `k8s/deployment.yaml` | `acs730-lab7-web`, 2 replicas of `acs730-lab4`, readiness and liveness probes on `/healthz`, CPU and memory requests and limits, runs as uid 10001 (non-root) |
| `k8s/service.yaml` | `acs730-lab7-svc`, NodePort 30080 to the container's port 8000, selected by `app: acs730-lab7-web` |
| `k8s/rbac.yaml` | ServiceAccount `acs730-lab7-deployer`, Role `acs730-lab7-deployer-role`, RoleBinding `acs730-lab7-deployer-binding` |
| `evidence/` | Week 9 and Week 10 evidence (table at the end) |

Everything runs in its own namespace, `acs730-lab7`, never `default`. The walkthrough calls it `lab7`; I named it with the `acs730-labN-<type>` convention I use for every resource in this course.

To rebuild everything from nothing (a stop and start of the workstation keeps the cluster, a lab reset doesn't): `scripts/create-cluster.sh` creates the kind cluster from `kind-cluster.yaml`, then `docker build -t acs730-lab4:week9 lab4/`, `kind load docker-image acs730-lab4:week9 --name acs730-lab7`, `kubectl apply -f k8s/namespace.yaml` on its own, then `kubectl apply -f k8s/`. The namespace goes first because `apply -f` on a folder sends the files in alphabetical order, so `configmap.yaml` and `deployment.yaml` would reach the API server before the namespace exists.

### Scripts

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/create-cluster.sh` | kind cluster `acs730-lab7` (Docker container `acs730-lab7-control-plane`) and the admin kubectl context `kind-acs730-lab7` | Nothing. An existing cluster is kept | None | Workstation, any folder |
| `scripts/make-deployer-kubeconfig.sh` | `/home/acs730-lab7-runner/.kube/config` (mode 600), a kubeconfig that logs in as the deployer ServiceAccount with a short-lived token. Replaces an older one | Its own temporary folder | `[duration]`, optional, default `24h`. Run again to renew the token | Workstation, as ec2-user (needs the admin context and sudo) |
| `scripts/teardown-runner.sh` | Nothing | The runner's systemd service and its registration in GitHub. Keeps the runner user, its files and the cluster, so the runner can be registered again for the Final Project | None | Workstation, as ec2-user, before stopping the instance |

### Workflows (repository root)

| Workflow | Runs on | Trigger | What it changes |
|---|---|---|---|
| `.github/workflows/lab7-ci.yml` | `ubuntu-latest` | Pull requests touching `lab7/` or the two Lab 7 workflows | Nothing. Runs `kubeconform` v0.8.0 with `-strict -summary` against the v1.31.0 schemas. Not a required check, so its `paths:` filter can't block other pull requests |
| `.github/workflows/lab7-deploy.yml` | `[self-hosted, acs730-lab7]` | Push to `main` touching `lab7/k8s/`, `lab4/` or the workflow itself, plus `workflow_dispatch`. Never `pull_request` | Builds `acs730-lab4:<first 12 of the commit SHA>`, loads it into kind, applies `configmap.yaml`, `deployment.yaml` and `service.yaml`, sets the new image, waits for the rollout, smoke-tests through the Service |

### Runner setup (done once by hand)

1. A dedicated user, `acs730-lab7-runner`, with `/sbin/nologin` and a private home folder, added to the `docker` group so it can build and `kind load`.
2. An iptables rule that rejects that user's traffic to the instance metadata service (169.254.169.254).
3. `make-deployer-kubeconfig.sh` to give it the deployer kubeconfig.
4. `libicu` installed (the runner's .NET runtime needs it on Amazon Linux 2023), then `config.sh` with a registration token fetched by `gh api`, so the token was never copied by hand or written to a file.
5. `.path` set to include `/usr/local/bin`, where kubectl and kind live, then `svc.sh install acs730-lab7-runner`, which runs it as a systemd service as that user.

## Why kind on EC2 and not EKS

Cost. An EKS cluster's control plane is billed at $0.10 an hour in standard support ([AWS pricing](https://aws.amazon.com/eks/pricing/)), which is about $73 a month (730 hours) before a single worker node. It's $0.60 an hour once a Kubernetes version reaches extended support. Our whole AWS Academy budget is $50. At $0.10 an hour the control plane alone uses it up in 500 hours, about 21 days, and that's before the worker EC2 instances, their EBS volumes and a load balancer for a `LoadBalancer` Service. The Learner Lab does allow `eks:CreateCluster`, so the limit isn't permissions, it's money: one forgotten cluster would end the account for the rest of the term.

kind runs the same Kubernetes API (v1.31.0 here) inside a Docker container on the workstation I'm already paying for. A t3.large is about $2 a day while it's running and nothing while it's stopped. Everything this lab is about (manifests, labels and selectors, probes, rollouts, RBAC, a pipeline that deploys and verifies) works the same on kind. What I give up is what a managed service adds: several nodes across availability zones, a control plane AWS keeps running, IAM-mapped access, and real load balancers. For a single-person lab that's a fair trade, and it's the same reasoning I'll use for the Final Project.

## Labels and selectors

A label is a key-value tag on an object. A selector is a query over labels, and it's how loosely connected objects find each other at runtime. Nothing in Kubernetes links to a Pod by name.

In this lab one label, `app: acs730-lab7-web`, does two jobs. The Deployment's `spec.selector.matchLabels` says which Pods it owns (through its ReplicaSet), and `spec.template.metadata.labels` stamps that same label on every Pod it creates, so the two must match. The Service's `spec.selector` uses it to pick which Pods get traffic, and the endpoints list (`kubectl get endpoints acs730-lab7-svc` shows two Pod IPs on port 8000 in `week09-kubectl-get-all.txt`) is the result.

What breaks depends on which selector is wrong. If the Deployment's selector doesn't match its own template, the API server rejects it (`apps/v1` checks that). The nasty case is the Service. A Service whose selector matches nothing is still accepted, still gets a ClusterIP and a NodePort, and every Pod still shows `Running 1/1`. Everything looks healthy, but `kubectl get endpoints` shows `<none>` and the curl hangs or is refused, because there's nothing behind the address. That's why `get endpoints` is the first thing I'd check when a Service doesn't answer.

Scaling shows the same loop from the other side (`week09-scaling.txt`): `kubectl scale --replicas=4` went from 2 Pods to 4, and the two new ones were 5 seconds old while the original two kept their age, so scaling up added Pods without restarting the ones already serving. Scaling back to 2 removed the new ones. Deleting a Pod didn't reduce the count: the ReplicaSet had a replacement running 2 seconds later. And a manual scale to 3 was undone by re-applying `deployment.yaml`, because the file's `replicas: 2` is the declared state.

The Service is `NodePort` because kind maps port 30080 of its node container to `127.0.0.1:30080` on the workstation (`kind-cluster.yaml`), and that's the only way in. `type: LoadBalancer` on kind waits forever for a load balancer nobody provides (Experiment 2).

## Why a GitHub-hosted runner can't deploy to this cluster

It's network reachability. A GitHub-hosted runner is a fresh VM in GitHub's cloud, on the internet. This cluster's API server is published only on the workstation's loopback interface, `127.0.0.1:35647` (see `docker ps` in the setup), and the NodePort only on `127.0.0.1:30080`. The workstation itself is in a VPC whose security group allows SSH from my IP and nothing else. There is no route from GitHub's network to that API server. Even with a valid kubeconfig, a hosted runner would be connecting to its own `127.0.0.1`. I'd only get past that by publishing the API server to the internet, which is far worse than the problem it solves.

The self-hosted runner works because it never needs an inbound connection. It dials out to GitHub over HTTPS (port 443), long-polls for jobs, runs them on the workstation, and reaches the cluster locally. Outbound HTTPS is already allowed, so no port is opened.

## The deploy pipeline

`lab7-deploy.yml` runs on the self-hosted runner, which logs in to the cluster as `acs730-lab7-deployer`. Each run shows this in its first step (`kubectl auth whoami`). The Role allows exactly what the pipeline does: `get`, `list`, `watch` and `patch` on Deployments, and `get` and `patch` on ConfigMaps and Services, in namespace `acs730-lab7` only. It has no `create`, `update` or `delete`, and no access to Secrets, Pods or RBAC objects. A person creates the objects once, and the pipeline can only change them. The deck's Role had `get`, `update` and `patch`. I dropped `update`, which nothing uses, and added `list` and `watch`, because `kubectl rollout status` lists and watches the Deployment rather than just getting it. `week10-auth-can-i.txt` checks every verb with `kubectl auth can-i`, runs the pipeline's real commands as the deployer, and shows reading Secrets, deleting a Pod and re-applying `rbac.yaml` all refused. Its last section has the five checks the walkthrough names, with a fresh token: patch deployments yes; delete deployments, get secrets, create namespaces and delete nodes all no.

The deployer can patch the ConfigMap (the pipeline applies `configmap.yaml`) but can't read the Secret, and the Pods still get `PLACEHOLDER_SECRET`. That's because the deployer never handles the Secret: the Deployment only names it in a `secretKeyRef`, and the kubelet on the node fetches the value with its own node credentials when it starts each container. Writing the reference needs `patch` on the Deployment; reading the value would need `get` on Secrets, which nothing in the pipeline does.

The order of the deploy steps matters:

1. `docker build` from `lab4/`, tagged with the commit SHA, never `:latest`. Every deploy is a new tag, so the Pod template changes and a rollout starts. With `:latest`, Kubernetes would also try to pull from Docker Hub.
2. `kind load docker-image`, because the kind node's containerd isn't the workstation's Docker. Without it the Pods sit in `ErrImagePull`.
3. `rollout pause`, `kubectl apply`, `kubectl set image`, `rollout resume`. Apply comes before set image. The other way round, apply would reset the image to the `week9` tag in `deployment.yaml` and the run would report success for the wrong build. The pause makes the manifest change and the new image one change, so each deploy is one revision. Without it, `apply` would briefly start a rollout back to the `week9` image, and that extra revision could be where `rollout undo` lands. A final `if: always()` step resumes the Deployment, so it's never left paused.
4. `kubectl rollout status --timeout=120s`. This is the gate. `set image` returns as soon as the API server accepts the change. `rollout status` waits until the new Pods are Ready and exits non-zero if they aren't, which fails the run.
5. A smoke test that curls `/healthz` through the Service, with retries.

The first run after merging (run 43163836244) deployed correctly but went red on its last step, "Record what is running", which asked for ReplicaSets and Pods. The deployer isn't allowed to list either, so RBAC refused my own workflow. I changed the step to read only the Deployment rather than widen the Role (PR #36). The next run, 43164334259, is green throughout (`week10-deploy-green.png`).

### The bad deploy and the rollback

PR #37 changed only the readiness probe's path to `/healthz-broken`. It's valid YAML, so `kubeconform` passed it, and so did every other check. A schema check can't know that the app has no such path. After the merge, run 43165026748 built and applied it. The new Pod started but never became Ready (`Readiness probe failed: HTTP probe failed with statuscode: 404`), `rollout status` timed out after 120 seconds, and the run failed (`week10-deploy-red.png`, `week10-deploy-red.txt`). With 2 replicas and the default rolling update, Kubernetes won't remove an old Pod until a new one is Ready, so the two old Pods kept serving and the site answered `HTTP/1.1 200 OK` throughout.

`kubectl rollout undo` (run by me with the admin context, not by the pipeline) put the cluster back on the last good build, `acs730-lab4:0b043e1eea35` with `/healthz`. That revision came back as revision 6, not 4, because an undo doesn't rewind history: it makes the old template the newest revision again (`week10-rollout-undo.txt`).

Undo doesn't fix the repository. It only changes the Deployment object in the cluster. `main` still said `/healthz-broken`, so the next merge touching `lab7/k8s/` or `lab4/` would have applied the bad probe again and broken the deploy a second time. Git is the source of truth, so the fix had to go through Git: PR #38 reverted the bad commit, the pipeline deployed from the fixed `main` (run 43166182440, green), and the end of `week10-rollout-undo.txt` shows the repo and the cluster both back on `/healthz`.

## Security of a self-hosted runner on a public repository

The risk: a self-hosted runner runs whatever a workflow tells it to, as the user it runs as, on a machine that also holds the cluster, Docker and the instance profile's LabRole credentials. This repository is public. If the deploy workflow ran on `pull_request`, anyone could fork the repo, change the workflow or the code it builds, open a pull request, and have their code run on my workstation. And the runner isn't wiped between jobs, so anything a job leaves behind is still there for the next one.

What I did about it:

- `lab7-deploy.yml` runs only on push to `main` (after a pull request and the required `summary` check) and on `workflow_dispatch`, which only someone with write access can start. It has no `pull_request` trigger. Pull-request checks (`lab7-ci`, `lab4-ci`) run on GitHub-hosted runners.
- The repository requires approval before workflows from any external contributor's fork pull request run.
- The runner runs as its own user, `acs730-lab7-runner`, with no login shell and a private home folder. It can't read ec2-user's admin kubeconfig, `~/.aws` or the course repo clone.
- Inside the cluster it's the deployer ServiceAccount, with a 24-hour token and the Role described above, limited to one namespace. `week10-auth-can-i.txt` shows Secrets, Pod deletion and RBAC changes refused.
- An iptables rule rejects the runner user's connections to the instance metadata service, so a job can't simply ask for LabRole credentials.
- The workflow token is `contents: read`, deploys run one at a time (`concurrency`), and the runner registration token was fetched with `gh api`, never pasted or committed.

What risk remains: the runner user is in the `docker` group, and Docker access is effectively root on the host. A malicious job could start a privileged container, read the kind node's admin kubeconfig (cluster-admin) and get round every RBAC rule above. My iptables rule only covers processes running as that user, so a container started by the job can still reach the metadata service and get LabRole credentials. The rule also isn't saved, so it's gone after a reboot until I add it again. All of this needs code to reach `main` first, through my account, a stolen GitHub token, or a compromised action (`actions/checkout@v5` is referenced by tag, which its owner could move). So the realistic exposure is "whoever can push to main owns the workstation". I accept that for a one-person lab account that's stopped when I'm not using it. In production I'd use ephemeral runners (or ARC) on isolated nodes, build images without the Docker socket, give the runner host no instance role or block metadata at the network level, and pin third-party actions to commit SHAs.

## Experiments

### 1. Kill a pod, with 2 replicas and with 1

**What happened.** With 2 replicas I deleted one Pod while curling `/healthz` every 0.2 seconds for 30 seconds: 138 requests, 0 failed, and the ReplicaSet had a replacement Running within seconds. With the Deployment scaled to 1 and that one Pod deleted, 5 of 129 requests failed, spread over about 2.9 seconds, until the replacement started and passed its readiness probe.

**Why.** When a Pod starts terminating it's removed from the Service's endpoints, so with two replicas the Service simply sends everything to the one still Ready. With one replica there's nothing left to send to until the new Pod is Ready, so every restart, crash or node drain is an outage. `replicas: 1` isn't a deployment strategy, it's a single point of failure with a restart policy.

### 2. Ask kind for a load balancer

**What happened.** I changed the Service to `type: LoadBalancer`. For the full two minutes `EXTERNAL-IP` stayed `<pending>`, `kubectl describe svc` showed `Events: <none>`, and there were no events for it at all: no error anywhere. The NodePort kept answering throughout. Re-applying `service.yaml` put it back to `NodePort`.

**Why.** A `LoadBalancer` Service only asks for a load balancer; a cloud controller has to answer by creating one, and kind has no cloud controller, so the request just waits, silently. It still works as a NodePort because `LoadBalancer` is built on top of one. On EKS the AWS cloud controller (or the AWS Load Balancer Controller) would create an Elastic Load Balancer, put its DNS name in `EXTERNAL-IP`, and start billing for it.

### 3. Make the pull policy lie

**What happened.** The image `acs730-lab4:b32b65cad3cb` was sitting in the node's image store (`crictl images` listed it). I set `imagePullPolicy: Always`, which changed the Pod template and started a rollout. The new Pod went to `ErrImagePull` and then `ImagePullBackOff`: `failed to resolve reference "docker.io/library/acs730-lab4:b32b65cad3cb": pull access denied, repository does not exist`. The two old Pods kept serving and `/healthz` answered the whole time. `kubectl rollout undo` put it back to `IfNotPresent`.

**Why.
