Ansible with AWS SSM — Agentless Configuration Management

    Overview
    This lab demonstrates how to use Ansible over AWS Systems Manager (SSM) to configure EC2 instances
    without SSH keys or open inbound ports. The control node connects to target nodes exclusively through
    the SSM Session Manager plugin, eliminating traditional key-pair management.
    Key highlights:
    
    Zero open inbound ports on target nodes (no port 22)
    No SSH key pairs required anywhere
    IAM role-based trust replaces credential management
    Dynamic EC2 inventory via amazon.aws.aws_ec2 plugin (tag-based filtering)
    Nginx installed and configured on two web servers from a single playbook run
    S3 bucket used as the SSM file-transfer channel

Project Structure

    Ansible-Dynamic-EC2-Inventory-Custom-Python-Inventory-Scripts/
    ├── README.md                        <- This file
    ├── ansible.cfg                      <- Ansible runtime configuration
    ├── site.yml                         <- Main playbook
    ├── inventory/
    │   └── hosts.aws_ec2.yml            <- Dynamic EC2 inventory (tag-filtered)
    └── files/
        └── nginx.conf                   <- Custom Nginx configuration

Prerequisites

    Requirement             Details
    AWS Account             IAM Admin access required
    IAM Permissions         Ability to create roles and attach managed policies

Architecture

      +--------------------------+          AWS Systems Manager
      |   ansible-control-node   |          (SSM Session Channel)
      |                          |
      |  - Ansible 2.16.x        |   SSM   +--------------------+
      |  - amazon.aws 7.2.0      +-------->+   web-server-01    |
      |  - community.aws 7.2.0   |         |   (AnsibleTarget)  |
      |  - session-manager-plugin|         +--------------------+
      |  - AnsibleControlRole    |
      |    (SSMFullAccess +      |   SSM   +--------------------+
      |     EC2ReadOnly)          +-------->+   web-server-02    |
      +--------------------------+         |   (AnsibleTarget)  |
                 |                         +--------------------+
                 | aws ec2 describe-instances
                 | (tag:Environment=production)
                 v
      +---------------------------+
      |   S3 Bucket               |
      |   ansible-ssm-bucket-*    |
      |   (SSM file transfer)     |
      +---------------------------+
    
      IAM Trust:
        EC2 Service --> AnsibleControlRole  (SSMFullAccess + EC2ReadOnly)
        EC2 Service --> AnsibleTargetRole   (SSMManagedInstanceCore)
    
      No SSH. No key pairs. No inbound port 22.

Step-by-Step Tasks

Task 1 — Create IAM Roles

    Go to IAM > Roles > Create Role in the AWS Console.
    Role 1: AnsibleTargetRole (for web servers)

    Trusted Entity : AWS Service -> EC2
    Policy         : AmazonSSMManagedInstanceCore
    Purpose        : Allows SSM Agent on the instance to register with AWS

    Role 2: AnsibleControlRole (for the control node)
    
    Trusted Entity : AWS Service -> EC2
    Policy 1       : AmazonSSMFullAccess       (to run SSM commands)
    Policy 2       : AmazonEC2ReadOnlyAccess   (to list instances for inventory)

Task 2 — Launch 3 EC2 Instances

    Go to EC2 > Launch Instance (repeat 3 times).
    
    Instance 1: ansible-control-node
    Name          : ansible-control-node
    AMI           : Ubuntu Server 22.04 LTS
    Instance Type : t2.micro
    IAM Role      : AnsibleControlRole
    Tags          : Name=ansible-control-node, Role=control
    
    Instance 2: web-server-01
    Name          : web-server-01
    AMI           : Ubuntu Server 22.04 LTS
    Instance Type : t2.micro
    IAM Role      : AnsibleTargetRole
    Security Group: Allow port 80 (HTTP) inbound
    Tags          : Name=web-server-01, Environment=production
    
    Instance 3: web-server-02
    Name          : web-server-02
    AMI           : Ubuntu Server 22.04 LTS
    Instance Type : t2.micro
    IAM Role      : AnsibleTargetRole
    Security Group: Allow port 80 (HTTP) inbound
    Tags          : Name=web-server-02, Environment=production
    
    [WARN] The Environment=production tag is how Ansible discovers target nodes.
    Missing this tag means the instance will not appear in inventory.

Task 3 — Register Target Nodes in SSM Fleet Manager

    Connect to each web server via EC2 Instance Connect.
    
    # Verify SSM Agent is running (Ubuntu 22.04 ships it pre-installed)
    sudo systemctl status amazon-ssm-agent
    
    # If not running, install and start it
    sudo snap install amazon-ssm-agent --classic
    sudo systemctl start amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent
    
    # Restart after IAM role changes (snap version requires snap restart)
    sudo snap restart amazon-ssm-agent

    Repeat on both web-server-01 and web-server-02.

    Verify in Fleet Manager:

    Go to Systems Manager > Fleet Manager. Both instances should show as Online.
    If instances are not visible:
    bash# Option A: Restart the SSM Agent (resolves most cases)
    sudo snap restart amazon-ssm-agent
    
    # Option B: Create the DHMC Service Linked Role (if DHMC is enabled)
    # Run from AWS CLI (local machine or control node after setup)
    aws iam create-service-linked-role \
      --aws-service-name ssm.amazonaws.com \
      --region your-region

    # Confirm the role was created
    aws iam get-role \
      --role-name AWSServiceRoleForAmazonSSM \
      --query 'Role.RoleName'


    [INFO] DHMC (Default Host Management Configuration) is an AWS feature that
    registers EC2 instances with SSM automatically. When enabled, it also requires
    a service-linked role. Use Option B only if the IAM role is attached, the SSM
    Agent is running, and the instance still does not appear in Fleet Manager.

    Note the instance IDs (needed for inventory confirmation):
        
    # Run from the control node after AWS CLI is installed (Task 4)
    aws ec2 describe-instances \
      --filters "Name=tag:Environment,Values=production" \
      --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
      --output table

Task 4 — Set Up the Control Node
    
    Connect to ansible-control-node via EC2 Instance Connect.


    Step 4.1 — Install Ansible and dependencies
    See setup-control-node.sh — run this script on the control node.


    Step 4.2 — Install AWS Collections
    # [WARN] Both collections are required. One alone is not sufficient.
    
    # Inventory plugin (discovers EC2 instances)
    ansible-galaxy collection install amazon.aws:==7.2.0 --force
    
    # Connection plugin (SSM transport for Ansible)
    ansible-galaxy collection install community.aws:==7.2.0
    
    # Verify both are installed at 7.2.0
    ansible-galaxy collection list | grep -E "amazon|community"
    
    # Confirm the SSM connection plugin exists
    find ~/.ansible/collections -name "aws_ssm.py" | grep connection


    Step 4.3 — Install the Session Manager Plugin

    curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
      -o "/tmp/session-manager-plugin.deb"
    
    sudo dpkg -i /tmp/session-manager-plugin.deb
    
    session-manager-plugin --version




