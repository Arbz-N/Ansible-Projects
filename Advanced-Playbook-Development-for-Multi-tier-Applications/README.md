# AnsibleRDSLab — AWS RDS MySQL Provisioning with Ansible


## Overview

    This project provisions an **AWS RDS MySQL** instance using Ansible and the `amazon.aws` collection.
    The playbook runs on `localhost` using boto3 to make AWS API calls — no target EC2 instance is required.
    A separate delete playbook handles teardown.

    Key highlights:
     - `connection: local` — Ansible calls AWS API directly from the control machine
     - `amazon.aws.rds_instance` module handles create and delete idempotently
     - `state: present` creates the instance only if it does not already exist
     - `register` captures the endpoint address for downstream tasks
     - `wait_for` blocks until MySQL port 3306 is accepting connections
     - A dedicated `RDS-delete.yaml` playbook cleanly removes the instance



## Project Structure


    Advanced-Playbook-Development-for-Multi-tier-Applications/
    |
    |-- RDS.yaml            # Playbook — create RDS MySQL instance
    |-- RDS-delete.yaml     # Playbook — delete RDS MySQL instance
    |
    |-- README.md




## Prerequisites

    Requirement         Check 
    
    Python 3.8+         python3 --version
    pip                 pip3 --version 
    Ansible 2.x         ansible --version
    AWS CLI             aws sts get-caller-identity

## Architecture

    Local Machine (control node)
            |
            | ansible-playbook RDS.yaml
            | connection: local
            | boto3 → AWS API
            v
    AWS RDS Service
            |
            v
    RDS MySQL Instance (my-rds)
      engine:    mysql
      class:     db.t3.micro
      storage:   20 GB
      port:      3306
      public:    false




## Task 1 — Install Dependencies

    
    # Install Ansible
    sudo apt update -y
    sudo apt install ansible awscli python3-pip -y
    
    # Install boto3 — required by the amazon.aws collection
    pip3 install boto3 botocore
    
    # Install the amazon.aws Ansible collection
    ansible-galaxy collection install amazon.aws
    
    # Verify
    ansible --version
    python3 -c "import boto3; print(boto3.__version__)"
    ansible-galaxy collection list | grep amazon




## Task 2 — Configure AWS Credentials


    aws configure
    # AWS Access Key ID:     your-access-key-id
    # AWS Secret Access Key: your-secret-access-key
    # Default region:        your-region
    # Output format:         json
    
    aws sts get-caller-identity
    # Confirms credentials are working




## Task 3 — Update Playbook Variables

    Open `RDS.yaml` and update the CONFIG values:
    
    
    region: "your-region"  # e.g. us-east-1
    master_user_password: "your-strong-password"

    Open `RDS-delete.yaml` and update:
    region: "your-region"


## Task 4 — Run the Playbook

    ### Syntax check
    
    ansible-playbook RDS.yaml --syntax-check
    # Expected: playbook: RDS.yaml


    ### Dry run
    
    ansible-playbook RDS.yaml --check
    # Simulates the run without making any changes

    
    ### Create the RDS instance
    
    ansible-playbook RDS.yaml
    # Takes 5–10 minutes to complete


    Expected output:
    
    PLAY [Create RDS database instance]
    
    TASK [Gathering Facts]
    ok: [localhost]
    
    TASK [Create RDS instance]
    changed: [localhost]
    
    TASK [Print RDS endpoint]
    ok: [localhost] => {
        "msg": "RDS Endpoint: my-rds.xxxxx.your-region.rds.amazonaws.com"
    }
    
    TASK [Wait for RDS instance to become available]
    ok: [localhost]
    
    PLAY RECAP
    localhost : ok=4  changed=1  unreachable=0  failed=0


### Verify via AWS CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-rds \
  --region your-region \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Engine:Engine,Class:DBInstanceClass}' \
  --output table
```

---

## Key Concepts

### `connection: local`

This tells Ansible not to SSH anywhere. All tasks run on the local machine using the local Python environment and boto3 to call AWS APIs directly.

### `state: present` and idempotency

The `amazon.aws.rds_instance` module checks whether the instance already exists before attempting to create it. Running the playbook a second time when the instance is already `available` produces `ok=4 changed=0` — no duplicate resources are created.

### `register` and `when`

`register: rds_result` stores the full module output. The `wait_for` task uses `when: rds_result.endpoint is defined` to ensure it only runs if an endpoint was actually returned — for example, if the instance was freshly created rather than already existing.

### Password security

The password is stored in plain text in this lab playbook. In production, use **Ansible Vault** to encrypt sensitive values:

```bash
ansible-vault encrypt_string 'your-strong-password' --name 'master_user_password'
```

---

## Real Errors and Fixes

### `ModuleNotFoundError: No module named 'boto3'`

```
Cause: boto3 not installed in the Python environment Ansible is using
Fix:   pip3 install boto3 botocore
       Confirm with: python3 -c "import boto3; print(boto3.__version__)"
```

### `amazon.aws.rds_instance module not found`

```
Cause: amazon.aws collection not installed
Fix:   ansible-galaxy collection install amazon.aws
```

### `NoCredentialsError`

```
Cause: AWS credentials not configured
Fix:   aws configure
       Verify with: aws sts get-caller-identity
```

### `DBInstanceAlreadyExists`

```
Cause: An RDS instance with the same identifier already exists
Fix:   This is expected on a second run — the module is idempotent
       The task will report ok instead of changed — no action is needed
```

### `wait_for` times out after 300 seconds

```
Cause: RDS provisioning took longer than 5 minutes, or security group blocks port 3306
Fix 1: Increase timeout value in RDS.yaml (e.g. timeout: 600)
Fix 2: If publicly_accessible is false, the wait_for task cannot reach port 3306
       from outside the VPC — remove or skip the wait_for task in that case
```

---

## Cleanup

### Delete via Ansible

```bash
ansible-playbook RDS-delete.yaml
```

### Delete via AWS CLI

```bash
aws rds delete-db-instance \
  --db-instance-identifier my-rds \
  --skip-final-snapshot \
  --region your-region

# Check deletion status
aws rds describe-db-instances \
  --db-instance-identifier my-rds \
  --region your-region \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
# Returns "deleting" then raises an error when fully removed
```

### Remove local files

```bash
rm -rf ~/ansible-lab
```

---

## License

MIT License