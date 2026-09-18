#!/usr/bin/env bash
set -euo pipefail
 
aws ec2 delete-security-group --group-name acs730-week1-sg
echo "Security group acs730-week1-sg deleted."
