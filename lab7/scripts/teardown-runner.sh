#!/usr/bin/env bash
# Lab 7: stop and deregister the self-hosted runner at the end of a session (handout step 11).
# Creates:   nothing
# Deletes:   the systemd service for runner acs730-lab7-runner, and the runner's registration in
#            GitHub. Keeps the user acs730-lab7-runner, its files and the kind cluster, so the runner
#            can be registered again for the Final Project.
# Arguments: none
# Run on:    the workstation, as ec2-user (needs sudo and gh logged in), before stopping the instance.
set -euo pipefail

REPO="jhui26-seneca/acs730-coursework"
RUNNER_USER="acs730-lab7-runner"
DIR="/home/$RUNNER_USER/actions-runner"

# 1. Stop and remove the systemd service (svc.sh writes .service when it installs one)
if sudo test -f "$DIR/.service"; then
  sudo bash -c "cd $DIR && ./svc.sh stop && ./svc.sh uninstall"
else
  echo "No runner service installed"
fi

# 2. Deregister from GitHub with a one-hour removal token fetched by gh (never written to a file)
if sudo test -f "$DIR/.runner"; then
  RT=$(gh api -X POST "repos/$REPO/actions/runners/remove-token" --jq .token)
  sudo -u "$RUNNER_USER" bash -c "cd ~/actions-runner && ./config.sh remove --token '$RT'"
  unset RT
else
  echo "Runner not registered"
fi

echo "--- proof"
echo "runners registered in GitHub: $(gh api "repos/$REPO/actions/runners" --jq .total_count)"
echo "runner services on this machine: $(systemctl list-units --all --no-legend 'actions.runner.*' | wc -l)"
