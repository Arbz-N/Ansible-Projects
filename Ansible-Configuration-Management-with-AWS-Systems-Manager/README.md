Ansible-Configuration-Management-with-AWS-Systems-Manager

    Overview
    This project demonstrates running Ansible playbooks over AWS Systems Manager (SSM) without opening SSH port 22. A control node discovers target instances dynamically via the SSM inventory plugin, and deploys Nginx to both web servers through SSM Run Command.
    Key highlights:
    
    No SSH keys or open port 22 required — SSM handles all communication
    Dynamic inventory via amazon.aws.aws_ssm plugin using EC2 tags
    Environment=production tag filters exactly the right instances
    Nginx installed, configured, and verified in a single playbook run
    Handler triggers Nginx restart only when the config file actually changes
    Tags on playbook tasks allow selective execution (--tags install, --tags verify)

Architecture:

        [Local Machine]
              |
              | SSH (port 22) — only for initial setup
              v
        [ansible-control-node]  (IAM: AnsibleControlRole)
              |
              | amazon.aws.aws_ssm inventory plugin
              | discovers instances tagged Environment=production
              |
              | ansible-playbook site.yml
              | connection: aws_ssm
              v
        AWS Systems Manager (SSM)
              |
              +-------+--------+
              |                |
              v                v
        [web-server-01]  [web-server-02]
        (AnsibleTargetRole)  (AnsibleTargetRole)
        Nginx installed      Nginx installed
        port 80 open         port 80 open

Project Structure:

    Ansible-Configuration-Management-with-AWS-Systems-Manager/
    |
    |-- ansible.cfg                  # Ansible configuration — inventory, user, plugins
    |-- site.yml                     # Main playbook — install and configure Nginx
    |
    |-- inventory/
    |   |-- aws_ssm.yml              # SSM dynamic inventory — discovers EC2 by tag
    |
    |-- files/
    |   |-- nginx.conf               # Custom Nginx configuration deployed to targets
    |
    |-- README.md

Prerequisites:

    - AWS Account with IAM admin access
    - Permission to launch 3 EC2 instances
    - AWS CLI configured on local machine (for verification only)

Task 1 — Create IAM Roles:

    Role 1: AnsibleTargetRole (for web-server-01 and web-server-02)
    IAM → Roles → Create role
    
      Trusted entity: AWS service → EC2
      Policy:         AmazonSSMManagedInstanceCore
      Role name:      AnsibleTargetRole
    
    → Create role

    Role 2: AnsibleControlRole (for ansible-control-node)
    IAM → Roles → Create role

      Trusted entity: AWS service → EC2
      Policies:
        - AmazonSSMFullAccess         (to run SSM commands)
        - AmazonEC2ReadOnlyAccess     (to list EC2 instances for inventory)
      Role name:      AnsibleControlRole
    
    → Create role

Task 2 — Launch 3 EC2 Instances:

    Instance 1: ansible-control-node
    EC2 → Launch Instance
    
      Name:            ansible-control-node
      AMI:             Ubuntu Server 22.04 LTS
      Instance type:   t2.micro
      Key pair:        your-key-pair
      Security group:  Allow inbound TCP port 22
      IAM role:        AnsibleControlRole
    
      Tags:
        Name = ansible-control-node
        Role = control
    Instance 2: web-server-01
      Name:            web-server-01
      AMI:             Ubuntu Server 22.04 LTS
      Instance type:   t2.micro
      Security group:  Allow inbound TCP port 80
      IAM role:        AnsibleTargetRole
    
      Tags:
        Name        = web-server-01
        Environment = production
        Role        = webserver
    Instance 3: web-server-02
      Name:            web-server-02
      AMI:             Ubuntu Server 22.04 LTS
      Instance type:   t2.micro
      Security group:  Allow inbound TCP port 80
      IAM role:        AnsibleTargetRole
    
      Tags:
        Name        = web-server-02
        Environment = production
        Role        = webserver


Task 3 — Register Target Nodes in SSM Fleet Manager

    SSH into each web server and verify the SSM agent:
    ssh -i your-key.pem ubuntu@<web-server-public-ip>
    
    sudo systemctl status amazon-ssm-agent
    # Should show: Active (running)
    
    # If not running:
    sudo snap install amazon-ssm-agent --classic
    sudo systemctl start amazon-ssm-agent
    sudo systemctl enable amazon-ssm-agent

    Verify in the console:
    Systems Manager → Fleet Manager
    Both web-server-01 and web-server-02 should appear with status Online.
    Note the instance IDs for both web servers — you will need them for --limit commands.

Task 4 — Set Up the Control Node

    SSH into ansible-control-node:
    ssh -i your-key.pem ubuntu@<control-node-public-ip>
    Install dependencies:
    sudo apt update -y && sudo apt upgrade -y
    sudo apt install ansible python3-pip awscli -y
    pip3 install boto3 botocore
    ansible-galaxy collection install amazon.aws
    
    ansible --version
    python3 --version
    aws sts get-caller-identity

    # AnsibleControlRole should appear in the output
    
    Set your region:

    aws configure set region your-region
    Verify target instances are visible:
    aws ec2 describe-instances \
      --filters "Name=tag:Environment,Values=production" \
      --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0]]' \
      --output table

Task 5 — Set Up Ansible Project
    
    mkdir -p ~/ansible-ssm-lab/{inventory,files}
    cd ~/ansible-ssm-lab
     Copy all files from this project into ~/ansible-ssm-lab/, maintaining the directory structure shown in the project structure section.

Test inventory discovery:

    ansible-inventory -i inventory/aws_ssm.yml --graph
    
    # Expected:
    # @all:
    #   |--@ungrouped:
    #   |  |--i-0abc123...   (web-server-01)
    #   |  |--i-0def456...   (web-server-02)

    Test connectivity:
    ansible all -m ping
    # Both instances should return: "ping": "pong"

Task 6 — Run the Playbook

    Dry run first
    ansible-playbook site.yml --check --diff
    # --check: simulate without making changes
    # --diff:  show what would change


    Full run
    ansible-playbook site.yml
    Expected output:
    PLAY RECAP
    i-0abc123... : ok=5 changed=4 unreachable=0 failed=0   (web-server-01)
    i-0def456... : ok=5 changed=4 unreachable=0 failed=0   (web-server-02)


Selective execution

    # Target a single server
    ansible-playbook site.yml --limit "i-0abc123..."
    
    # Run specific task groups only
    ansible-playbook site.yml --tags install
    ansible-playbook site.yml --tags configure
    ansible-playbook site.yml --tags verify
    
    # Verbose debug output
    ansible-playbook site.yml -vvv

Task 7 — Verify

    From the control node
    ansible all -m command -a "systemctl status nginx"
    ansible all -m command -a "nginx -t"
    ansible all -m command -a "curl -s http://localhost"

    From the browser
    http://<web-server-01-public-ip>
    http://<web-server-02-public-ip>
    Each page displays the server's instance ID confirming which node served the response.

    From the AWS console
    Systems Manager → Run Command → Command History
    Both targets should show Success with a 2/2 completion count.


