# OS Security Hardening with Ansible and AWS Config

    Overview
    This project applies CIS-aligned security hardening to Ubuntu servers using an Ansible role,
    then enables AWS Config for continuous compliance monitoring. 
    A compliance audit playbook checks each hardening control and outputs a per-host pass/fail report.
    Key highlights:
    
    Ansible role structure with tasks, defaults, and handlers directories
    UFW firewall configured with default-deny and explicit allow rules
    SSH hardened — root login, password auth, X11 forwarding and TCP forwarding disabled
    Unused kernel filesystem modules disabled via /etc/modprobe.d
    auditd installed and enabled for system call auditing
    Insecure packages (telnet, rsh-client, talk) removed
    AWS Config enabled with an S3 delivery channel for compliance history
    Compliance audit playbook produces a [PASS]/[FAIL] report per host

Project Structure

    OS-Security-Hardening-with-Ansible-and-AWS-Config/
    |
    |-- site.yaml                                    # Main hardening playbook
    |-- compliance_audit.yaml                        # Compliance check playbook
    |-- aws_config_setup.yaml                        # Enable AWS Config
    |-- inventory.ini                                # Static inventory (update IPs)
    |-- config-trust-policy.json                     # IAM trust policy for AWS Config
    |
    |-- roles/
    |   |-- security_hardening/
    |       |-- tasks/
    |       |   |-- main.yml                         # Hardening tasks
    |       |-- defaults/
    |       |   |-- main.yml                         # Default variables
    |       |-- handlers/
    |           |-- main.yml                         # SSH restart handler
    |
    |-- README.md

Prerequisites:

    Requirement            Check
    
    Ansible 2.x            ansible --version
    AWS CLI                aws sts get-caller-identity
    boto3                  python3 -c "import boto3; print(boto3.__version__)"
    amazon.aws             ansible-galaxy collection install amazon.aws
    community.general      ansible-galaxy collection install community.general

    sudo apt install tree -y
    pip install boto3
    ansible-galaxy collection install amazon.aws community.general

Architecture:

    Ansible Control Node
            |
            | SSH / SSM
            v
    Target Servers (node1, ...)
      |-- Update packages
      |-- UFW firewall (default deny, allow 22/80/443)
      |-- SSH hardening (no root, no password auth)
      |-- Disable unused filesystem modules
      |-- Install and enable auditd
      |-- Remove telnet, rsh-client, talk
            |
            v
    Compliance Audit → [PASS]/[FAIL] per control
    
    Ansible Control Node
            |
            | boto3 → AWS API
            v
    AWS Config (us-east-1)
      |-- Configuration Recorder (all resources)
      |-- Delivery Channel → S3 bucket
      |-- Continuous compliance history

Task 1 — Update Inventory
    
    Open inventory.ini and replace:
        
        YOUR_NODE_IP with the actual IP address of your target node
        your-key.pem with the actual path to your SSH private key

Task 2 — Create IAM Role for AWS Config:

    aws iam create-role \
      --role-name AWSConfigRole \
      --assume-role-policy-document file://config-trust-policy.json
    
    aws iam attach-role-policy \
      --role-name AWSConfigRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRole
    
    CONFIG_ROLE_ARN=$(aws iam get-role \
      --role-name AWSConfigRole \
      --query 'Role.Arn' --output text)
    echo "Config Role ARN: $CONFIG_ROLE_ARN"

Task 3 — Run the Hardening Playbook:

    cd ~/ansible_project
    
    # Syntax check
    ansible-playbook -i inventory.ini site.yaml --syntax-check
    
    # Dry run
    ansible-playbook -i inventory.ini site.yaml --check
    
    # Apply hardening
    ansible-playbook -i inventory.ini site.yaml -v

    Expected output:

    TASK [security_hardening : Update and upgrade all packages]
    changed: [node1]
    
    TASK [security_hardening : Enable UFW with default deny policy]
    changed: [node1]
    
    PLAY RECAP
    node1 : ok=8  changed=6  unreachable=0  failed=0

Task 4 — Enable AWS Config:
    
    ansible-playbook aws_config_setup.yaml -v

Task 5 — Run Compliance Audit:

    # Print report to screen
    ansible-playbook -i inventory.ini compliance_audit.yaml
    
    # Save report to file
    ansible-playbook -i inventory.ini compliance_audit.yaml \
      | tee compliance-report-$(date +%Y%m%d).txt

    Sample output:

    ============================================
    COMPLIANCE AUDIT REPORT
    Host : node1
    Date : 2026-04-01
    ============================================
    SSH Root Login Disabled : PASS
    Firewall Active         : PASS
    Password Auth Disabled  : PASS
    Audit Logging Active    : PASS
    ============================================

Key Concepts:

    Ansible Role Structure
    A role separates concerns into standard directories. 
    Ansible automatically loads tasks/main.yml, defaults/main.yml, and handlers/main.yml 
    when the role is referenced in a playbook. This makes roles reusable across multiple playbooks and projects.
    
    Handlers
    The Restart SSH handler in handlers/main.yml runs only when notified by the SSH hardening task. 
    If the sshd_config file is already correct and no change is made, 
    the handler is never triggered — avoiding unnecessary service restarts.
    
    ignore_errors and changed_when in audit tasks
    Compliance checks use shell: grep ... to test a condition. If the grep finds no match it exits with code 1, 
    which Ansible normally treats as a failure. ignore_errors: yes prevents the play from stopping, and changed_when: 
    false ensures the task always reports ok rather than changed regardless of output.
    
    AWS Config delivery channel
    The S3 bucket receives configuration snapshots and change history. 
    AWS Config can trigger AWS Lambda or SNS when a resource drifts from its expected state — enabling automated remediation.

Cleanup:

    # Disable and delete AWS Config
    aws configservice stop-configuration-recorder \
      --configuration-recorder-name default \
      --region your-region
    
    aws configservice delete-configuration-recorder \
      --configuration-recorder-name default
    
    # Delete IAM role
    aws iam detach-role-policy \
      --role-name AWSConfigRole \
      --policy-arn arn:aws:iam::aws:policy/service-role/AWSConfigRole
    aws iam delete-role --role-name AWSConfigRole
    
    # Remove local files
    rm -rf ~/ansible_project
    rm -f config-trust-policy.json compliance-report-*.txt

License:

    MIT License