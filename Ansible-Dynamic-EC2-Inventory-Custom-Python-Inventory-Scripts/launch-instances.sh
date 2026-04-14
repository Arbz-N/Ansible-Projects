#!/usr/bin/env bash
# launch-instances.sh — Create the two EC2 test instances for the lab
# Run from: any machine with the AWS CLI configured and EC2 launch permissions
# Usage   : bash launch-instances.sh

set -euo pipefail

# ============================================================
# CONFIG — replace all placeholder values before running
# ============================================================
REGION="your-region"          # e.g. us-east-1
AMI_ID="ami-XXXXXXXXXXXXXXXXX" # Ubuntu 22.04 LTS AMI for your region
                               # Find in EC2 Console > AMIs > search "ubuntu 22.04"
INSTANCE_TYPE="t3.micro"
KEY_NAME="your-key-pair"       # Name of your existing EC2 key pair (no .pem)
# ============================================================

echo "[INFO] Launching web-server-1..."
WEB_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[
      {Key=Name,Value=web-server-1},
      {Key=Environment,Value=prod},
      {Key=Role,Value=webserver}
    ]" \
  --region "${REGION}" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "[OK] web-server-1 launched: ${WEB_INSTANCE_ID}"
# Tags: Environment=prod, Role=webserver
# Inventory groups: tag_Environment_prod, tag_Role_webserver, all

echo "[INFO] Launching db-server-1..."
DB_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --key-name "${KEY_NAME}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[
      {Key=Name,Value=db-server-1},
      {Key=Environment,Value=prod},
      {Key=Role,Value=database}
    ]" \
  --region "${REGION}" \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "[OK] db-server-1 launched: ${DB_INSTANCE_ID}"
# Tags: Environment=prod, Role=database
# Inventory groups: tag_Environment_prod, tag_Role_database, all

echo ""
echo "[INFO] Waiting for instances to reach running state..."
aws ec2 wait instance-running \
  --instance-ids "${WEB_INSTANCE_ID}" "${DB_INSTANCE_ID}" \
  --region "${REGION}"

echo "[OK] Both instances are running."
echo ""
echo "[INFO] Instance summary:"
aws ec2 describe-instances \
  --instance-ids "${WEB_INSTANCE_ID}" "${DB_INSTANCE_ID}" \
  --region "${REGION}" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table

echo ""
echo "[INFO] Next: run python3 aws-dynamic-inventory.py to verify inventory."