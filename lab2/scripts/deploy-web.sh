#!/usr/bin/env bash
set -euo pipefail

# Lab 2: deploy the web page. Run as the service user, not root.
SERVICE_USER="acs730-lab2-user"

if [ "$(whoami)" != "$SERVICE_USER" ]; then
  echo "Please run this as ${SERVICE_USER}:  sudo su - ${SERVICE_USER}"
  exit 1
fi

# Step 5: install with the package manager
sudo dnf install -y httpd

# Write the page, then FIX OWNERSHIP (sudo tee leaves it owned by root)
echo "<h1>ACS730 Lab 2 - deployed by ${SERVICE_USER} on $(hostname)</h1>" \
  | sudo tee /var/www/html/index.html > /dev/null
sudo chown "${SERVICE_USER}:${SERVICE_USER}" /var/www/html/index.html

sudo systemctl start httpd

echo "--- local check:"
curl -s localhost | head -3
ls -l /var/www/html/index.html
