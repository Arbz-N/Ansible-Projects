#!/bin/bash
# userdata.sh
# Runs automatically when a new instance is launched from the ASG Launch Template
# Paste this content into the User Data field under Advanced Details

# Enable and start the SSM Agent (pre-installed on Ubuntu 22.04)
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent

# Install AWS CLI
sudo apt update -y
sudo apt install -y awscli

# Retrieve instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Tag the instance so Ansible dynamic inventory can discover it
aws ec2 create-tags \
  --resources "$INSTANCE_ID" \
  --tags Key=Environment,Value=production Key=ManagedBy,Value=Ansible \
  --region "$REGION"