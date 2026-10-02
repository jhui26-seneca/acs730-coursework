# Lab 2 - Linux Administration and Deploying a Web App to EC2

This lab deploys a small static web application to a dedicated Amazon Linux 2023 test instance (`acs730-lab2-web`), entirely by script from my acs730-workstation, and proves with a reboot test that systemd brings it back with nobody logging in.

## Deployment steps (what deploy-web.sh does, in order)

1. Installs `python3` with `dnf` (safe to repeat: dnf does nothing if it is already installed).
2. Creates the no-login service user `acs730-lab2-svc`, only if it does not already exist.
3. Writes `index.html` into `/opt/acs730-lab2-web` and makes `acs730-lab2-svc` its owner.
4. Copies `acs730-web.service` into `/etc/systemd/system/` and runs `daemon-reload`.
5. Runs `systemctl enable` and `systemctl restart` for `acs730-web`, then checks the page with `curl localhost`.

## systemctl start vs enable

`systemctl start` runs a service now but is forgotten at the next boot, while `systemctl enable` links it into the boot sequence so systemd starts it automatically after every reboot, so a real service needs both.

## Why SSH is a /32 but HTTP is 0.0.0.0/0

SSH is administrative access, so only the one machine I administer from (the workstation's public IP, a /32) may reach port 22. HTTP is the service the public is meant to reach, so port 80 is open to everyone. Least privilege means each port is open to exactly the audience that needs it, and no wider.

## Which user runs the application, and why not root

The web server runs as `acs730-lab2-svc`, a system account with no home directory, no password and `/sbin/nologin` as its shell. If someone found a bug in Python's `http.server`, they would get only what that account can do: read the web files, with no shell and no sudo. The unit grants the one privilege it needs, binding port 80, through `AmbientCapabilities=CAP_NET_BIND_SERVICE`, and `NoNewPrivileges=true` stops it gaining more. I did the admin work as my own named sudo user, `acs730-lab2-admin`, so actions are attributable to a person rather than to the shared `ec2-user`.

## Scripts and files

| File | Creates | Deletes | Arguments | Run on |
|---|---|---|---|---|
| `scripts/create-key-pair.sh` | Local ed25519 key `~/.ssh/acs730-lab2-key` (if missing) and AWS key pair `acs730-lab2-key` (public half only) | - | none | workstation |
| `scripts/delete-key-pair.sh` | - | AWS key pair `acs730-lab2-key` (local file kept) | none | workstation |
| `scripts/create-security-group.sh` | Security group `acs730-lab2-sg`: tcp/22 from the workstation's /32, tcp/80 from 0.0.0.0/0 | - | none | workstation |
| `scripts/create-instance.sh` | AL2023 t3.micro `acs730-lab2-web` with that key and group, no instance profile | - | none | workstation |
| `scripts/create-admin-user.sh` | Admin user `acs730-lab2-admin` (wheel, SSH key, sudoers rule); the only step that logs in as `ec2-user` | - | none | workstation |
| `scripts/deploy-web.sh` | `python3` package, service user `acs730-lab2-svc`, `/opt/acs730-lab2-web/index.html`, the `acs730-web` unit (enabled and started) | - | none | test instance, as `acs730-lab2-admin` |
| `scripts/capture-evidence.sh` | `evidence/security-group-rules.json`, `service-<label>-reboot.txt`, `http-<label>-reboot.txt` | - | `before` or `after` | workstation |
| `scripts/delete-instance.sh` | - | Instance `acs730-lab2-web` (waits for instance-terminated) | none | workstation |
| `scripts/delete-security-group.sh` | - | Security group `acs730-lab2-sg` | none | workstation |
| `acs730-web.service` | systemd unit: runs `python3 -m http.server 80` as `acs730-lab2-svc`, restarts on failure, starts at boot | - | - | installed by deploy-web.sh |

## Evidence

`evidence/caller-identity.png` (LabRole identity), `security-group-rules.json` (exactly two ingress rules), `service-before-reboot.txt` / `service-after-reboot.txt` (enabled, active, process owned by `acs730-lab2-svc`, later boot time after the reboot) and `http-before-reboot.txt` / `http-after-reboot.txt` (`HTTP/1.0 200 OK` from the workstation).

## Experiments
