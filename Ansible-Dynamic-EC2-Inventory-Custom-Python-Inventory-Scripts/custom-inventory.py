#!/usr/bin/env python3
# custom-inventory.py
# Simple diagnostic script — verifies boto3 connectivity and prints
# a human-readable summary of all running EC2 instances.
#
# NOTE: This script is NOT Ansible-compatible.
#       It does not implement --list / --host.
#       Use aws-dynamic-inventory.py for Ansible integration.
#
# Usage: python3 custom-inventory.py

# ============================================================
# CONFIG
# ============================================================
REGION = "your-region"   # e.g. us-east-1
# ============================================================

import boto3
import json


def get_ec2_instances():
    """Query EC2 and return a summary of running instances."""

    ec2_client = boto3.client("ec2", region_name=REGION)

    # Fetch only instances that are currently running.
    # Stopped and terminated instances are excluded to keep output clean.
    response = ec2_client.describe_instances(
        Filters=[
            {"Name": "instance-state-name", "Values": ["running"]}
        ]
    )

    ip_addresses = []
    regions = set()
    tags = set()

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:

            # Only include instances that have a public IP assigned.
            # Instances in private subnets without NAT will have no public IP.
            if "PublicIpAddress" in instance:
                ip_addresses.append(instance["PublicIpAddress"])

            # Availability Zone (e.g. us-east-1a) — not the region itself.
            regions.add(instance["Placement"]["AvailabilityZone"])

            # Collect all tags as "Key: Value" strings for display.
            # .get("Tags", []) avoids a KeyError on instances with no tags.
            for tag in instance.get("Tags", []):
                tags.add(f"{tag['Key']}: {tag['Value']}")

    result = {
        "IP_Addresses": ip_addresses,
        "Regions": list(regions),
        "Tags": list(tags),
    }

    print(json.dumps(result, indent=4))


if __name__ == "__main__":
    get_ec2_instances()