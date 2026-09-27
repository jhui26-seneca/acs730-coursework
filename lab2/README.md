# Lab 2 - Linux Administration and Deploying a Web App to EC2

This lab deploys a simple Apache web page to a dedicated Amazon Linux 2023 test instance (`acs730-lab2-web`), entirely by script from my acs730-workstation. The instance uses a custom SSH key pair (`acs730-lab2-key`) and a least-privilege security group (`acs730-lab2-sg`) that allows SSH only from the workstation's /32 address and HTTP from anywhere. The page is deployed by `scripts/deploy-web.sh`, running as a dedicated non-root user (`acs730-lab2-user`), which installs httpd with dnf and sets the page's ownership to that user. Apache is managed by a custom systemd unit (`acs730-web.service`), and a reboot test confirmed that the web server came back automatically with no manual steps.

## systemctl start vs enable

`systemctl start` runs a service immediately but has no effect after the next boot, while `systemctl enable` registers the service to start automatically at every boot, so a production service needs both.

## Contents

- `scripts/` - create and delete scripts for the key pair, security group and instance; `deploy-web.sh` for the web page; `capture-evidence.sh` for the before/after checks
- `acs730-web.service` - the systemd unit file
- `evidence/` - security group rules (`sg-rules.txt`) and service status before and after the reboot (`service-before-reboot.txt`, `service-after-reboot.txt`)

## Run order

From the repo root on the workstation: `create-key-pair.sh`, `create-security-group.sh`, `create-instance.sh`, then `deploy-web.sh` on the test instance as `acs730-lab2-user`. Teardown: `delete-instance.sh` (which waits for termination), `delete-security-group.sh`, `delete-key-pair.sh`.

# Lab 2

Instructions for this section will be provided in class and on Blackboard when we reach it.

Put your work for Lab 2 in this folder.
