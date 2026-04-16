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
    
    Step 4.4 — Verify SSM connectivity

    aws ssm describe-instance-information \
      --query 'InstanceInformationList[].[InstanceId,PingStatus,ComputerName]' \
      --output table
    # [OK] PingStatus should show "Online" for both web servers

Task 5 — Create the Ansible Project

    mkdir -p ~/ansible-ssm-lab/{inventory,files,roles}
    cd ~/ansible-ssm-lab
    
    
    Step 5.1 — Create ansible.cfg
    See ansible.cfg — copy it to ~/ansible-ssm-lab/ansible.cfg.
    
    
    Step 5.2 — Create an S3 bucket for SSM file transfer
    # SSM uses S3 to transfer files between the control node and targets
    aws s3 mb s3://ansible-ssm-bucket-your-account-id --region your-region
    
    # Confirm it was created
    aws s3 ls | grep ansible-ssm
    
    
    Step 5.3 — Create the inventory file
    See hosts.aws_ec2.yml — copy it to ~/ansible-ssm-lab/inventory/hosts.aws_ec2.yml.
    
    [WARN] The filename must end in .aws_ec2.yml. The plugin's verify_file()
    method rejects files that do not match this pattern.


    Step 5.4 — Test the inventory

    ansible-inventory -i inventory/hosts.aws_ec2.yml --graph
    # [OK] Both web server instance IDs should appear under @all
    
    ansible all -m ping
    # [OK] Both instances should return {"ping": "pong"}

Task 6 — Create the Playbook

    Step 6.1 — Create nginx.conf
    See nginx.conf — copy it to ~/ansible-ssm-lab/files/nginx.conf.


    Step 6.2 — Create site.yml
    See site.yml — copy it to ~/ansible-ssm-lab/site.yml.
    bash# Validate the playbook syntax before running
    ansible-playbook site.yml --syntax-check
    # [OK] Should print "playbook: site.yml" with no errors

Task 7 — Run the Playbook

    # Dry run first — shows what will change without making changes
    ansible-playbook site.yml --check --diff
    
    [WARN] During dry run, you may see:
    "Could not find the requested service nginx: host"
    This is expected. Nginx is not installed yet so the service module
    cannot find it. The actual run will succeed.

    # Full run — installs and configures Nginx on both web servers
    ansible-playbook site.yml

    Expected output:
    PLAY RECAP -------------------------------------------------------
    i-XXXXXXXXXXXXXXXXX : ok=5  changed=4  unreachable=0  failed=0
    i-XXXXXXXXXXXXXXXXX : ok=5  changed=4  unreachable=0  failed=0
    Targeted runs:

    # Run against a single instance
    ansible-playbook site.yml --limit "i-XXXXXXXXXXXXXXXXX"
    
    # Run only tasks tagged 'install'
    ansible-playbook site.yml --tags install
    
    # Verbose output for debugging
    ansible-playbook site.yml -vvv

Task 8 — Verify Deployment

    From the control node:
    
    # Check Nginx service status on both servers
    ansible all -m command -a "systemctl status nginx"
    
    # Validate Nginx configuration syntax
    ansible all -m command -a "nginx -t"
    
    # Confirm the deployed page is served
    ansible all -m command -a "curl -s http://localhost"
    # [OK] Should return the custom HTML page

    From a browser:
    http://web-server-01-PUBLIC-IP
    http://web-server-02-PUBLIC-IP
    
    [WARN] Ensure port 80 is open in the Security Group attached to both web servers.
    
    From the AWS Console:
    Go to Systems Manager > Run Command > Command History. Ansible's SSM
    connection plugin issues AWS-RunShellScript commands. Successful runs appear
    with status Success and 2/2 targets.







