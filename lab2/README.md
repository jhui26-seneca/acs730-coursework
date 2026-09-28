# Lab 2 - Linux Administration and Deploying a Web App to EC2

This lab deploys a simple Apache web page to a dedicated Amazon Linux 2023 test instance (`acs730-lab2-web`), entirely by script from my `acs730-workstation`. The instance uses a custom SSH key pair (`acs730-lab2-key`) and a least-privilege security group (`acs730-lab2-sg`) that allows SSH only from the workstation's /32 address and HTTP from anywhere. The page is deployed as a dedicated non-root user (`acs730-lab2-user`), Apache is managed by a custom systemd unit (`acs730-web.service`), and a reboot test confirmed that the web server came back automatically with no manual steps.

## systemctl start vs enable

`systemctl start` runs a service immediately but has no effect after the next boot, while `systemctl enable` registers the service to start automatically at every boot, so a production service needs both.

## Scripts

All scripts are in `scripts/`. Every create and delete script checks before acting, so running it twice is harmless.

| Script | Creates | Deletes | Arguments | Run on / as |
|---|---|---|---|---|
| `create-key-pair.sh` | A local ed25519 key pair `~/.ssh/acs730-lab2-key` (+ `.pub`) if it does not exist, and imports the public half into AWS as key pair `acs730-lab2-key` | Nothing | None | Workstation |
| `create-security-group.sh` | Security group `acs730-lab2-sg` with two inbound rules: TCP 22 from the workstation's public IP `/32` (looked up with checkip.amazonaws.com) and TCP 80 from `0.0.0.0/0`. Exits without changes if the group already exists | Nothing | None | Workstation |
| `create-instance.sh` | One `t3.micro` Amazon Linux 2023 instance (latest AMI from SSM), tagged `Name=acs730-lab2-web`, using `acs730-lab2-key` and `acs730-lab2-sg`, with no instance profile; waits until it is running and prints its public IP. Skips if the instance already exists | Nothing | None (needs the key pair and security group first) | Workstation |
| `deploy-web.sh` | Installs `httpd` with dnf, writes `/var/www/html/index.html`, changes its owner to `acs730-lab2-user`, and starts `httpd` | Nothing | None. Refuses to run unless the current user is `acs730-lab2-user` | Test instance, as `acs730-lab2-user` (copied to `/tmp/` with scp) |
| `capture-evidence.sh` | The evidence file `evidence/service-<label>-reboot.txt` (overwritten each run): boot time, enabled state of `acs730-web` and `httpd`, `systemctl status`, `index.html` ownership, and both curl checks. Creates no AWS resources | Nothing | Required: `before` or `after` | Workstation (connects to the test instance by SSH) |
| `delete-instance.sh` | Nothing | Terminates every instance tagged `acs730-lab2-web` (pending, running, stopping or stopped) and waits until it is terminated | None | Workstation |
| `delete-security-group.sh` | Nothing | Security group `acs730-lab2-sg`, if it exists | None. Run after `delete-instance.sh` | Workstation |
| `delete-key-pair.sh` | Nothing | Key pair `acs730-lab2-key` in AWS; the local private key in `~/.ssh/` is kept | None | Workstation |

## Other files

- `acs730-web.service` - systemd unit (`Type=oneshot`) that runs `systemctl start httpd` at boot; installed to `/etc/systemd/system/` and enabled. `httpd` itself is left disabled, so the reboot test proves the unit works.
- `evidence/sg-rules.txt` - the security group rules (port 22 from a single /32, port 80 from 0.0.0.0/0)
- `evidence/service-before-reboot.txt`, `evidence/service-after-reboot.txt` - service status before and after the reboot

## Run order

1. On the workstation, from the repo root: `create-key-pair.sh`, `create-security-group.sh`, `create-instance.sh`
2. On the test instance as `acs730-lab2-user`: `deploy-web.sh`; then install and enable `acs730-web.service`
3. On the workstation: `capture-evidence.sh before`, reboot the test instance, `capture-evidence.sh after`
4. Teardown on the workstation: `delete-instance.sh`, `delete-security-group.sh`, `delete-key-pair.sh`
