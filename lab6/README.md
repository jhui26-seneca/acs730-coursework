# Lab 6 - Ansible Configuration Management and Golden AMIs

Terraform creates two tagged web servers in the default VPC with LabInstanceProfile and no port 22 ingress at all. Ansible finds them by tag and configures them over AWS Systems Manager, from the workstation and from GitHub Actions in the step straight after `terraform apply`. Packer bakes the same `webserver` role into a golden AMI, and both approaches are timed from the launch request to the page being served.

## The three answers

I used Ansible over Session Manager (the `aws_ssm` connection), because the SSM agent on each instance dials out using LabInstanceProfile, so neither the workstation nor the GitHub runner needs a stored SSH key and port 22 is never opened; Packer reaches its build instance the same way, through an SSM port-forward with a temporary key it creates and deletes in the same run. A second run reporting changed=0 proves that every task checked the real state of the host and found it already matched what the role asks for, which is what makes the same command safe on a new instance, a converged one, and from a pipeline on every merge. Deregistering an AMI only deletes the image record: the EBS snapshot behind it is the stored data and the thing that bills, it stays behind, and once the AMI is gone `describe-images` can no longer tell you which snapshot belonged to it, so teardown reads the snapshot ID first and deletes it after.

## Boot-to-ready

| Approach | Launch request to page served | What the time includes |
|---|---|---|
| Plain Amazon Linux 2023, then Ansible over SSM | 83 s (`evidence/boot-to-ready-ansible.txt`) | Launch 20 s, SSM agent Online at 21 s, then about 62 s of playbook (dnf installs httpd, template, service start) |
| Golden AMI baked by Packer with the same role | 24 s (`evidence/boot-to-ready-golden.txt`) | Launch 20 s, then httpd is already installed and enabled, so the page is up 4 s later |

The page itself says which path built it: `Build: ansible-converge` on the converged instance, and `Build: golden-ami` on the one launched from the image, where Packer overrode `webserver_build_tag` with `--extra-vars`. The golden instance also serves `/baked.html` (HTTP 200), a static file Packer copied in after the role ran; the converged instance returns 404 for it, because the role never creates that file.

In the slow path the time didn't go into Ansible's own logic. SSM registered after one second this time (on another day it can take 30 to 60 s), and most of the 62 s was dnf pulling httpd and its dependencies over the network, which happens again on every instance at every launch.

A golden AMI doesn't remove that work, it moves it: the same role runs once at bake time (the Packer build took 4 min 38 s) instead of once per launch. So the image wins as soon as I launch more than a couple of instances, or launch them often, and it loses for a single instance, where I'd pay a full Packer build to save about a minute.

Each approach breaks in its own way. An image is frozen at bake time: security updates released after the bake aren't in it, so it needs a rebuild schedule, and you can't see what's inside it without the build log, whereas the playbook is its own documentation. Converge-on-boot depends on the package mirrors and SSM being reachable at the moment of launch: if a mirror is down, instances boot and never become ready, and an autoscaling event at 3 a.m. is exactly when I don't want a network dependency in the boot path.

My recommendation: golden AMI for these web servers, because they're launched in groups and should come up in seconds, with the playbook kept in the pipeline to catch drift on running hosts; I'd switch to converge-on-boot for a server I launch once and change often, where rebuilding an image for every change costs more than the minute it saves.

One constraint worth knowing: Ansible's SSM connection copies each module through an S3 bucket, and the bucket, `ansible_aws_ssm_region` and the instances all have to be in us-east-1. Experiment 5 shows what a mismatch looks like.

## Experiments

### 1. A shell command instead of a module

**What happened.** I added a task that runs `mkdir -p /var/www/html/logs` through `ansible.builtin.shell`. Both runs reported `changed=1` on both hosts, even though the directory already existed by the second run. With `creates: /var/www/html/logs` added, both runs reported `changed=0`.

**Why.** A shell command is opaque to Ansible: it can't look inside it to know what it does, so it runs it and reports changed every time. `creates:` gives Ansible something to check first: if the path exists, it skips the command. The `file` module has that check built in, which is why the role uses modules.

### 2. `state: latest` versus `state: present`

**What happened.** I changed the dnf task to `state: latest` and ran it twice. Both runs reported `changed=0`. `dnf check-update` on both hosts showed no newer httpd packages that night.

**Why.** `latest` means "the newest version the repository has today", so the result depends on the day: on any day Amazon publishes an httpd update, the same playbook reports changed and quietly upgrades a package mid-pipeline. `present` only means "installed", which stays true. In a pipeline that runs on every merge I want `present`, with upgrades done on purpose, for example by rebuilding the golden AMI, not as a side effect of an unrelated merge.

### 3. Drift by hand versus a change in code

**What happened.** Through SSM Run Command I deleted the `Build:` line from `index.html` on one host only. The next run, with `--diff`, showed the line being added back, `changed` on that host's template task and its restart handler, and `ok` on the other host; the run after that was `changed=0` on both. Then I changed `webserver_title` in `defaults/main.yml`: both hosts reported `changed=2` (template and handler).

**Why.** Both cases show up as "changed" in the recap, but they're opposite situations. In the first, the server drifted away from the code, and Ansible put one host back to what the code already said. In the second, the code changed, and every host had to follow it. The handler fired in both cases only because the template task notified it, and only on the hosts where the template actually changed.

### 4. The inventory shrinks

**What happened.** I stopped (not terminated) one instance. `ansible-inventory --graph` then showed one host in `@role_web`, with nothing edited. With the `instance-state-name: running` filter removed, the stopped instance came back into the inventory, and the playbook failed on it with `TargetNotConnected ... is not connected` (counted as `failed=1`, not unreachable) while the running host finished `changed=0`. With the filter back and the instance started again, it rejoined and reported `changed=0`.

**Why.** The aws_ec2 plugin asks the EC2 API for the host list on every run, so the inventory follows reality without anyone editing a file. The state filter is what keeps it to hosts that can actually answer; without it, EC2 still knows the stopped instance and its tags, but SSM can't open a session to it.

### 5. Breaking the SSM connection two ways

**What happened.** With `ansible_aws_ssm_region` set to us-west-2 (bucket still in us-east-1), the ping failed on both hosts with `TargetNotConnected ... is not connected`, not the `PermanentRedirect` bucket error I'd read about. Then I removed `iam_instance_profile` from `main.tf` and replaced one instance: it ran with no instance profile, never appeared in `aws ssm describe-instance-information` after three minutes, still appeared in the inventory, and its ping failed with the same `TargetNotConnected`. After putting the profile back and replacing it again, SSM reported the new instance Online, the first converge still failed on it, and the next run configured it (`changed=4`).

**Why.** In the first case Ansible opened the session in us-west-2, where these instances don't exist, so it failed before it ever reached the bucket. In the second, the instance had no credentials to register with SSM at all. The inventory comes from EC2 tags, not SSM, so it listed the instance anyway. Neither error message names its cause: both say only "not connected", and I had to infer the wrong region from the config and the missing profile from `describe-instance-information`. The `aws_ssm` connection plugin now ships in the amazon.aws collection (`ansible-doc` lists `amazon.aws.aws_ssm`); it was previously in community.aws, the name `group_vars/role_web.yml` uses.

## Terraform (terraform/main.tf)

| Creates / changes | Deletes | Notes |
|---|---|---|
| Two instances `acs730-lab6-web-0` and `-1` (`instance_count`, default 2; tags Role=web, Lab=lab6; LabInstanceProfile; IMDSv2), security groups `acs730-lab6-sg` (port 80 from the VPC only) and `acs730-lab6-packer-sg` (no ingress) | Everything above, via `terraform destroy` (run by `scripts/teardown.sh`) | Default VPC, subnet in us-east-1a; state in `acs730-tfstate-<account>`, key `lab6/terraform.tfstate`. The SSM bucket is not in Terraform: the Academy account's service control policy denies `s3:GetBucketObjectLockConfiguration`, which the AWS provider reads after creating any bucket, so `scripts/create-ssm-bucket.sh` creates it instead. |

## Ansible (ansible/)

| File | Purpose |
|---|---|
| `ansible.cfg` | Points at the dynamic inventory and the roles folder |
| `inventory/lab6.aws_ec2.yml` | amazon.aws.aws_ec2 plugin; running instances tagged Role=web and Lab=lab6; keyed_groups builds group `role_web`; no IDs or IPs in the file |
| `group_vars/role_web.yml` | SSM connection, bucket and region (all us-east-1) |
| `site.yml` | Applies the `webserver` role with become to `hosts: all`, so the inventory decides which machines run and Packer's build instance (in no group) is matched too |
| `roles/webserver/` | tasks (dnf, template, service), defaults (including `webserver_build_tag`), a restart handler, and `templates/index.html.j2` with no timestamps |

## Packer (packer/)

| File | Creates | Notes |
|---|---|---|
| `web.pkr.hcl` | AMI `acs730-lab6-golden-<timestamp>` and its snapshot; a temporary build instance and key pair that Packer removes itself | Runs the same `../ansible/site.yml` through the ansible provisioner with `webserver_build_tag=golden-ami`; connects through Session Manager and uses `acs730-lab6-packer-sg`, so no port-22 group is ever created |
| `files/index.html` | Nothing (copied into the image as `/var/www/html/baked.html`) | A static page decided once at bake time; the role never manages it |

## Scripts (scripts/)

| Script | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `create-ssm-bucket.sh` | S3 bucket `acs730-lab6-ssm-<account>` in us-east-1 with all public access blocked (skips creation if it exists) | Nothing | None | Workstation, once per session, before the first Ansible run |
| `wait-for-ssm.sh` | Nothing | Nothing | Optional instance ID; default = every running Role=web, Lab=lab6 instance | Workstation and CI |
| `boot-to-ready.sh` | One t3.micro `acs730-lab6-b2r-<mode>` and `evidence/boot-to-ready-<mode>.txt` | That instance, when timing ends | Required: `ansible` or `golden` | Workstation |
| `teardown.sh` | `evidence/teardown.txt` | Leftover timing instances, every `acs730-lab6-golden-*` AMI and its snapshots, everything Terraform created, and the SSM bucket with its contents | None | Workstation |

## Workflow (.github/workflows/lab6-configure.yml)

| Event | What it does |
|---|---|
| Pull request touching lab6/** | Terraform fmt, validate and plan |
| Push to main (or manual run) | Installs Ansible, boto3 and session-manager-plugin first; then `terraform init`, `terraform apply`, and in the very next step "Converge the instances with Ansible" (wait for SSM Online, inventory graph, playbook); then a second run that fails the job if anything reports changed |

## Evidence

- `caller-identity.png` - workstation identity
- `inventory-graph.txt` - the tag-built `role_web` group with both instances
- `idempotency-run1.txt`, `idempotency-run2.txt` - the second run reports changed=0 on both hosts
- `pipeline-run.png` - the merge-triggered run, with "Converge the instances with Ansible" directly after "terraform apply"
- `packer-build.txt`, `golden-ami.png` - the bake (the role's tasks run inside it) and the resulting AMI
- `boot-to-ready-ansible.txt`, `boot-to-ready-golden.txt` - the timings, with the Build line and baked.html check
- `teardown.txt` - everything removed, including the snapshot and the SSM bucket
