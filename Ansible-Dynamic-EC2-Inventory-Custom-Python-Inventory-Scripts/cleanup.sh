#!/usr/bin/env bash
# cleanup.sh — Remove all lab resources to stop AWS charges
# Run on : ansible-control-node (before terminating instances)
# Usage  : bash cleanup.sh

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
REGION="your-region"
ACCOUNT_ID="your-account-id"
S3_BUCKET="ansible-ssm-bucket-${ACCOUNT_ID}"
# ============================================================

echo "[INFO] Step 1 — Removing Nginx from all target nodes via Ansible..."
ansible all -m apt -a "name=nginx state=absent purge=yes" --become
# purge=yes removes Nginx config files from /etc/nginx as well.
# Without purge, configuration files are left behind even after uninstall.

echo "[INFO] Step 2 — Deleting S3 bucket..."
aws s3 rb "s3://${S3_BUCKET}" --force --region "${REGION}"
# --force empties the bucket before deleting it.
# Without --force, the delete fails if any objects remain in the bucket.
echo "[OK] S3 bucket deleted: ${S3_BUCKET}"

echo "[INFO] Step 3 — Deleting lab files from control node..."
rm -rf ~/ansible-ssm-lab
echo "[OK] ~/ansible-ssm-lab removed"

echo "[INFO] Step 4 — Detaching and deleting IAM roles..."

# AnsibleTargetRole — web servers
aws iam detach-role-policy \
  --role-name AnsibleTargetRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam delete-role --role-name AnsibleTargetRole
echo "[OK] AnsibleTargetRole deleted"

# AnsibleControlRole — control node
aws iam detach-role-policy \
  --role-name AnsibleControlRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess
aws iam detach-role-policy \
  --role-name AnsibleControlRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
aws iam delete-role --role-name AnsibleControlRole
echo "[OK] AnsibleControlRole deleted"

echo ""
echo "[OK] Cleanup complete."
echo ""
echo "[WARN] Manual step required — terminate all 3 EC2 instances in the AWS Console:"
echo "       EC2 > Instances > select ansible-control-node, web-server-01, web-server-02"
echo "       Instance State > Terminate Instance"
echo ""
echo "[INFO] Terminate (not Stop) to end EBS storage charges as well."