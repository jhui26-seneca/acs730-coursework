# Assignment 2 - Configuration Management Automation with Ansible and Packer

**Report** - John Hui (GitHub `jhui26-seneca`), ACS730, October 2026. Repository: `jhui26-seneca/acs730-coursework`, folder `assignment2/`. File-by-file details and scripts are in `README.md`; every claim below points to a file in `evidence/`.

## Introduction

The brief asks for one end state - an Apache web server serving a known page - reached two ways: configured after boot by an Ansible role, and baked ahead of time into a golden AMI by Packer. Everything else in the assignment exists to make that comparison honest: a dynamic inventory so Ansible finds whatever Terraform built, an idempotency proof so the role is safe to run repeatedly, a pipeline step so the converge happens automatically after every apply, and two timings taken from the same clock positions.

I made one design decision early, because it shapes everything after it: there is exactly one definition of the server. The `webserver` role configures the live servers over SSM, and Packer bakes the golden AMI by running the same role against its build instance. A change to the page, the package or the Apache settings is made once and reaches both paths.

The work ran in an AWS Academy Learner Lab account, which set three constraints. IAM writes are denied, so GitHub Actions reaches AWS with session-scoped credentials held in a GitHub Environment rather than through OIDC. The account's service control policy denies some calls the tools make by default - one of them stopped my first Packer build at its last step (Task 5). And the budget is fixed, so everything was built and destroyed in one session. The work was delivered in two pull requests: #31 (targets, inventory, role, pipeline) and #32 (golden AMI, timings, teardown and this report).

## Task 1 - Dynamic inventory

Terraform (`terraform/main.tf`, based on my Lab 6 configuration, with `lab6/` left unchanged) creates two `t3.micro` web servers in the default VPC with `LabInstanceProfile`, IMDSv2 only, and a security group that allows HTTP from inside the VPC and has no port 22 rule at all. Every instance carries two tags: `Role = web` on the instance and `Assignment = assign2` through the provider's default tags. Those tags are the contract between the two tools - Terraform writes them, Ansible queries them, and neither tool needs to know anything else about the other.

`ansible/inventory/assign2.aws_ec2.yml` uses the `amazon.aws.aws_ec2` plugin (enabled in `ansible.cfg`) to ask AWS at run time for running instances with both tags, and builds the group `role_web` from the `Role` tag with `keyed_groups`. Hosts are named by instance ID (`hostnames: instance-id`) because the SSM connection addresses an instance by its ID; a side effect is that no IP address appears in any Ansible output. There is no host list, instance ID or IP address anywhere in the repository's code - I checked with `grep` before each commit - and `evidence/inventory-graph.txt` shows the result: `@role_web` containing both instances, discovered from the tag.

The connection settings live in `group_vars/role_web.yml`, so they apply only to hosts in that group. That turned out to matter in Task 5, where Packer's build host is deliberately not in `role_web`.

## Task 2 - The role

The role was generated with `ansible-galaxy role init --init-path roles webserver` and keeps the generated layout - `tasks/`, `defaults/`, `handlers/`, `templates/`, `files/`, `vars/`, `meta/`, `tests/` and a README - shown in `evidence/role-tree.txt`. (`files/` holds a `.gitkeep` only because Git does not store empty directories.) The play that calls it, `site.yml`, is four lines: hosts `role_web`, `become: true`, role `webserver`.

`tasks/main.yml` has four tasks, each a module with a desired state: `ansible.builtin.dnf` with `state: present`, two `ansible.builtin.template` tasks, and `ansible.builtin.service` with `state: started` and `enabled: true`. All module names are fully qualified and all arguments are YAML dictionaries. Every value the tasks and templates use comes from `defaults/main.yml`, so a play can override any of them.

There are two templates, both rendering values from the defaults. `index.html.j2` renders the page title and message. `acs730-httpd.conf.j2` renders an Apache drop-in, `/etc/httpd/conf.d/acs730.conf`, that sets `ServerTokens` and `ServerSignature` to stop Apache advertising its version and the operating system. Only the settings file notifies the `Restart web server` handler; a new page is served without a restart, so the page task does not notify it. `evidence/template-rendered.txt` is the proof that the templates actually rendered: both files read back off both servers with the values substituted. A `curl -I` against each server then returned `Server: Apache` with no version, which is the settings template taking effect.

One small trap is worth recording: `ServerSignature Off` has to be written as `"Off"` in the defaults, because an unquoted `Off` is YAML for `false` and would have rendered as `ServerSignature False`. The rendered file shows `Off`.

## Task 3 - Idempotency

I wrote the role for idempotency from the first task rather than fixing it afterwards: no `shell` or `command` tasks, `state: present` rather than `latest`, one task owning each file, a handler instead of a restart task, and templates with no timestamps, host names or anything else that changes between runs.

The proof is two identical runs of `ansible-playbook site.yml`, back to back, with nothing edited in between:

| Run | Time (UTC) | Both servers |
|---|---|---|
| `evidence/idempotency-run1.txt` | 09:07:57 | `ok=6 changed=5 failed=0` - package installed, settings and page written, service started and enabled, handler restarted Apache |
| `evidence/idempotency-run2.txt` | 09:09:04 | `ok=5 changed=0 failed=0` - every task reported `ok`, and the handler did not run because nothing notified it |

`changed=0` on the second run means the role describes a state rather than a list of steps: each task checked the server, found it already correct and did nothing. That is what makes it safe to run on every merge, and what lets the same run correct drift if someone edits a server by hand.

## Task 4 - Pipeline integration

`.github/workflows/assign2-deploy.yml` sits at the repository root and is scoped with `paths: ['assignment2/**']`. On a pull request it only runs `terraform fmt`, `validate` and `plan`. On a push to `main` its `deploy` job installs the tools first - pinned Ansible (`>=12,<13`, the same 2.19 line as my workstation), boto3 and the Session Manager plugin - so that the step list reads **Terraform apply** followed immediately by **Ansible converge**, which waits for SSM and runs `site.yml`. A final step runs the play a second time and fails the job if any host reports `changed` or `failed` above zero. The workflow sets `shell: bash`, which makes GitHub run every step with `pipefail`; without it, `ansible-playbook ... | tee` would report success even when Ansible failed.

The merge of PR #31 ran it for real (run 39575896174, green in 1 minute 37 seconds; `evidence/pipeline-run.png`). The pull request's plan had said `No changes`, which also proved the credentials worked; the apply said `No changes`, and the converge and the second run both reported `changed=0` on both servers, because the workstation had already configured them.

**Connection method: Option A, Ansible over SSM.** I chose `community.aws.aws_ssm` because it removes the problem rather than managing it:

- **No inbound access at all.** The SSM agent on each server connects outward to Systems Manager using `LabInstanceProfile`. The security group has no port 22 rule, so there is nothing for a scanner to find and no rule to forget to remove.
- **No second credential.** The runner reaches the servers with the same session-scoped AWS credentials it already uses for Terraform, read from the `assign2` GitHub Environment. Those credentials die with the Academy session, within about four hours.
- **File transfer stays private.** Ansible copies its modules through the S3 bucket `acs730-assign2-ssm-<account>`, with all public access blocked. I gave it its own bucket rather than reusing my Week 3 state bucket: the state bucket has versioning on, so every module Ansible copies through it would stay behind as an old object version. The bucket is created by a script rather than Terraform, because the Academy's service control policy denies a read the Terraform provider makes after creating any bucket (found in Lab 6).

Option B, an ephemeral key pair per run, would also avoid a stored key, but it still needs port 22 open to the runner. GitHub-hosted runners come from a very large and changing range of addresses, so in practice that means either a near-world-open rule or adding and removing an exact-address rule on every run - more moving parts, and an open port during every deploy. Option A has neither.

Because Assignment 1 moved my AWS secrets into GitHub Environments and deleted the repository copies, this workflow uses a third environment, `assign2`, with no reviewer. `refresh-gha-creds.sh ... staging prod assign2` writes the session credentials to all three each session. Assignment 1's least-privilege setup stays as it was: the `assign2` job cannot read `prod`'s copy.

The only `0.0.0.0/0` in the code is in the two security groups' **outbound** rules, which the SSM agent, `dnf` and S3 need. Nothing is open inbound to the internet.

## Task 5 - The golden AMI

`packer/web.pkr.hcl` builds the AMI from the same standard Amazon Linux 2023 image the servers use. Packer's Ansible provisioner runs `ansible/bake.yml` - the same `webserver` role, applied to `hosts: all` because Packer hands Ansible a one-host inventory named `default`. That host is not in `role_web`, so the SSM settings in `group_vars/role_web.yml` do not apply; Ansible connects through Packer's own tunnel instead (`use_proxy = false`, using Packer's temporary key). Packer itself reaches the build instance with `ssh_interface = "session_manager"` and uses the security group `acs730-assign2-packer-sg`, which has no inbound rules, so it never creates its own temporary group with port 22. The build was run from the workstation, as the course guidance recommends, after `bake.yml` had been tested against the live servers (`changed=0` on both).

`packer validate` passed. The first build ran the role cleanly (`ok=6 changed=5`) and created the AMI, then failed at its very last step: setting the AMI's description is a separate `ec2:ModifyImageAttribute` call, and the Academy's service control policy denies it. Packer deregistered the AMI, deleted its snapshot and terminated the build instance on its own, and I confirmed nothing was left. I removed the description and built again. The second build finished in 7 minutes 4 seconds (`real 7m6.8s` from `time`; `evidence/packer-build.txt`) and produced `ami-09aa9cd6223cb2891`, backed by snapshot `snap-09ec6c758beface48`. `evidence/ami-describe.json` records its name, creation date (09:48:19 UTC) and tags - including `ConfiguredBy = ansible-role-webserver` and `SourceAMIName`, which pins down exactly which base image was baked - and `evidence/golden-ami.png` shows it in the console with the snapshot on the Storage tab. The build log shows Packer used my security group, created no temporary group and authorised no port.

## Task 6 - Boot-time comparison

Both instances were launched the same way, by a small separate Terraform configuration (`terraform/timing/`), driven by `scripts/boot-to-ready.sh`. Both evidence files state the same two clock positions above the result:

- **Clock start:** the moment `terraform apply` is started for one fresh `t3.micro`.
- **Clock stop:** the first `curl` of the instance's home page that returns HTTP 200 with the assignment's page.

| | Stock AL2023 + Ansible role over SSM | Golden AMI |
|---|---|---|
| Starting image | `al2023-ami-2023.12.20261016.0-kernel-6.1` | Baked from that same image |
| `terraform apply` finished | +24 s | +24 s |
| SSM agent online | +26 s | not needed |
| Converge (5 changes) | 66 s | not needed |
| **Launch to first HTTP 200** | **92 s** (`evidence/boot-to-ready-ansible.txt`) | **30 s** (`evidence/boot-to-ready-golden.txt`) |

The launch cost the same 24 seconds both ways; the 62-second difference is almost entirely the converge - installing httpd and rendering two files at boot, which the golden AMI did once, at build time, in about 7 minutes. SSM registered unusually quickly (2 seconds after the apply); on a slower day it would add time to the Ansible path only.

One correction made the comparison fair. My first Ansible measurement was 96 seconds, but its stock image had kernel 6.18 while the AMI was baked on kernel 6.1. The image filter `al2023-ami-2023.*-x86_64` matched both kernel variants of the same release, published at the same second, so "most recent" was a tie that Terraform and Packer broke differently. I pinned the filter to `al2023-ami-2023.*-kernel-6.1-x86_64` in all three places and re-measured. "Latest" is not a version - which is part of the Task 7 argument.

## Task 7 - Which approach for which team

My numbers say where the time goes, not that one approach is free. Baking cost 7 minutes once and saved 62 seconds on every launch. Converging costs nothing up front and 66 seconds on every new server, but a run over servers that are already correct is cheap: in the pipeline, the second converge over both servers took about 18 seconds and changed nothing.

**A team deploying dozens of times a day: converge with Ansible, on a lightly baked base image.** At that rate, most deploys change the page, the configuration or the application, not the operating system. With the role in the pipeline, a change reaches every running server in the next run - one converge, about a minute and a half end to end in my run - and the second-run check proves it settled. Baking a full AMI for each of those deploys would mean at least a 7-minute build plus replacing every instance, dozens of times a day, and each new image would differ from the last in more ways than the change being shipped. What this team should bake is the slow-moving layer - the OS, httpd and patches - on a schedule, so that a scale-out instance only converges the small fast-moving layer and pays seconds, not the 66 seconds my stock instance paid. The risk this accepts is that a launch depends on SSM and the package mirror; baking the packages removes the mirror from that risk.

**A team deploying once a month: a golden AMI, rebuilt every release and at least monthly for patches.** Seven minutes of build time once a month is nothing, and in exchange every launch takes 30 seconds, is predictable, and cannot fail on a slow mirror or a late SSM registration - which matters most at the moment the team least wants surprises, during a scale-out. What is running is auditable as one image ID, with its base recorded in the `SourceAMIName` tag. The cost of this model is staleness: a monthly image is a monthly-patched fleet, so the rebuild has to be scheduled rather than left until the next feature, and an urgent patch means a rebuild and a rolling replacement rather than one playbook run.

**Where the upstream changes.** The converge model installs whatever the mirror offers on the day a server is built, so two servers launched a week apart can differ; `state: present` also never upgrades a server that already has the package. The golden model freezes one known version, consistent across the fleet but ageing from the day it was built. My own run showed the same thing at the image level: an unpinned "latest" filter gave Terraform and Packer two different images within the hour.

**For an autoscaling group versus a few long-lived servers:** an autoscaling group should launch from a golden image, because boot time is paid on every scale-out and nobody is there to retry a failed converge. A handful of long-lived servers suits converging, because they boot rarely and the playbook's real value is correcting drift on servers that live for months.

## Task 8 - Cleanup

`scripts/teardown.sh` removed everything in dependency order and recorded it in `evidence/teardown.txt`: no timing instance was left; it deregistered `ami-09aa9cd6223cb2891` and then deleted `snap-09ec6c758beface48` - deregistering alone would have left the snapshot billing; `terraform destroy` removed both servers and both security groups (`4 destroyed`); and it deleted the SSM bucket and its contents. It ends with proof that nothing is left - no instance, AMI, snapshot, security group, Packer key pair or bucket for the assignment, and both Terraform states empty - and `cleanup-check.sh` found nothing unexpected. Only my workstation and the term-long state bucket remain.

## Conclusion

The comparison came out as expected - 92 seconds against 30 - but the more useful result is where the time went. The golden AMI did not make configuration faster; it moved 66 seconds of work from every launch to a 7-minute build, and in exchange made the fleet as old as its last build. Converging keeps everything current and correctable at the price of work, and a dependency, at every boot.

If I were running this service, I would adopt both, split by how often each layer changes: a base image baked by Packer on a schedule with the operating system, httpd and patches, and the same Ansible role applied by the pipeline for everything that changes between those builds. Using one role for both is what makes that practical - the line between baked and applied can move without writing anything twice.

Three lessons go beyond the tools. First, write for idempotency from the first task: the second run was `changed=0` the first time because nothing in the role could rewrite itself. Second, a platform's restrictions show up at the worst moment - my first Packer build failed at its last call, after all the real work had succeeded - so it pays to read the error against what actually exists before rebuilding. Third, "latest" is not a version: an ambiguous image filter quietly gave my two paths different starting points, and only recording the source image made it visible.
