#!/usr/bin/env bash
# cleanup.sh — Terminate all EC2 instances created in the lab
# Run from: any machine with the AWS CLI configured
# Usage   : bash cleanup.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
REGION="your-region"   # e.g. us-east-1
# ============================================================

echo "[INFO] Finding instances tagged for this lab..."

# Collect instance IDs for all instances tagged Environment=prod.
# This matches both web-server-1 (Role=webserver) and db-server-1 (Role=database).
INSTANCE_IDS=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Environment,Values=prod" \
    "Name=instance-state-name,Values=running,stopped" \
  --region "${REGION}" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

if [ -z "${INSTANCE_IDS}" ]; then
  echo "[WARN] No instances found with tag Environment=prod in ${REGION}."
  exit 0
fi

echo "[INFO] Instances to terminate:"
echo "${INSTANCE_IDS}"
echo ""

read -rp "[WARN] This will permanently terminate the instances above. Continue? (yes/no): " CONFIRM
if [ "${CONFIRM}" != "yes" ]; then
  echo "[INFO] Cleanup cancelled."
  exit 0
fi

echo "[INFO] Terminating instances..."
aws ec2 terminate-instances \
  --instance-ids ${INSTANCE_IDS} \
  --region "${REGION}" \
  --query 'TerminatingInstances[].[InstanceId,CurrentState.Name]' \
  --output table

echo "[OK] Termination initiated."
echo "[INFO] Instances will reach 'terminated' state within a few minutes."
echo "[INFO] Terminated instances no longer incur compute charges."