#!/usr/bin/env python3
# aws-dynamic-inventory.py
# Ansible-compatible dynamic inventory for AWS EC2.
#
# Implements the Ansible external inventory contract:
#   --list  : return full inventory JSON (groups + _meta.hostvars)
#   --host  : return variables for a single host (returns {} when _meta is used)
#
# Group naming: tags are converted to group names in the form tag_KEY_VALUE.
#   Example: Role=webserver  -> group: tag_Role_webserver
#            Environment=prod -> group: tag_Environment_prod
#
# Usage
#   python3 aws-dynamic-inventory.py          (same as --list)
#   ansible -i aws-dynamic-inventory.py all -m ping

# ============================================================
# CONFIG
# ============================================================
REGION = "your-region"   # e.g. us-east-1
# ============================================================

import boto3
import json
import sys


def get_inventory():
    """
    Query EC2 for all running instances and build an Ansible-compatible
    inventory object with tag-based groups and per-host variables.
    """

    ec2_client = boto3.client("ec2", region_name=REGION)

    response = ec2_client.describe_instances(
        Filters=[
            {"Name": "instance-state-name", "Values": ["running"]}
        ]
    )

    # Ansible inventory structure.
    # "all" is the built-in group that contains every host.
    # "_meta.hostvars" stores per-host variables in the --list response,
    # which prevents Ansible from calling --host once per host (API efficiency).
    inventory = {
        "all": {"hosts": []},
        "_meta": {"hostvars": {}},
    }

    # tag_groups accumulates groups derived from instance tags.
    # Built separately and merged at the end to keep the logic clear.
    tag_groups = {}

    for reservation in response["Reservations"]:
        for instance in reservation["Instances"]:

            ip = instance.get("PublicIpAddress")

            # Skip instances with no public IP — Ansible cannot reach them
            # over SSH without additional proxy or VPN configuration.
            if not ip:
                continue

            # Every reachable instance belongs to "all".
            inventory["all"]["hosts"].append(ip)

            # Store useful per-host facts in hostvars.
            # These are accessible in playbooks as:
            #   hostvars[inventory_hostname]["instance_id"] etc.
            inventory["_meta"]["hostvars"][ip] = {
                "instance_id":    instance["InstanceId"],
                "region":         instance["Placement"]["AvailabilityZone"],
                "instance_type":  instance["InstanceType"],
                "state":          instance["State"]["Name"],
            }

            # Build tag-based groups from every tag on the instance.
            # Spaces in keys or values are replaced with underscores to produce
            # valid Ansible group names (spaces are not allowed).
            for tag in instance.get("Tags", []):
                key   = tag["Key"].replace(" ", "_")
                value = tag["Value"].replace(" ", "_")
                group = f"tag_{key}_{value}"

                if group not in tag_groups:
                    tag_groups[group] = {"hosts": []}

                tag_groups[group]["hosts"].append(ip)

    # Merge tag groups into the main inventory.
    inventory.update(tag_groups)

    return inventory


if __name__ == "__main__":
    # Ansible calls the script with --list to get the full inventory.
    # It calls --host HOSTNAME to get variables for a specific host,
    # but only when _meta.hostvars is NOT present in the --list output.
    # Since we always include _meta, --host is never called in practice.
    # The branch below satisfies the interface contract for older Ansible versions.

    if len(sys.argv) > 1 and sys.argv[1] == "--host":
        # Variables already provided in _meta.hostvars — return empty dict.
        print(json.dumps({}))
    else:
        # Default: return the full inventory (--list behavior).
        print(json.dumps(get_inventory(), indent=4))