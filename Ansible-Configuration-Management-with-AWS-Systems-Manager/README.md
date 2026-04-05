# Ansible Configuration Management with AWS Systems Manager

    Overview
    This project demonstrates using Ansible with AWS Systems Manager (SSM) to manage EC2 instances without SSH.
    A playbook installs and configures Nginx on all instances in the web_servers inventory group. 
    Execution is triggered through SSM Run Command, and instances are discovered automatically via the SSM dynamic inventory plugin.
    
    [Control Node — Ansible installed]
            |
            | ansible-playbook nginx_playbook.yml
            v
    AWS SSM (no SSH required)
            |
            v
    EC2 Target Instances (SSM Agent running, Role=web tag)
            |
            v
    Nginx installed, configured, and running on port 80


# Project Structure:

    AnsibleLab/
    |
    |-- ansible.cfg               # Ansible configuration (inventory, user, SSH args)
    |-- aws_ssm_inventory.yml     # SSM dynamic inventory — discovers EC2 instances
    |-- nginx.conf                # Custom Nginx configuration file
    |-- nginx_playbook.yml        # Playbook — install, configure and start Nginx
    |
    |-- README.md

# Prerequisites:

    - AWS Account with admin access
    - EC2 instance(s) as targets (Amazon Linux 2 or Ubuntu)
    - Control node (local machine or separate EC2) with Ansible installed
    - AWS CLI configured: aws configure
    - Python 3.8+

### Task 1 — Set Up AWS Systems Manager:

    Attach IAM Role to Target EC2 Instances
    IAM → Roles → Create role
    
      Trusted entity: AWS service → EC2
      Policy:         AmazonSSMManagedInstanceCore
    
      Role name: EC2-SSM-Role
    
    → Create role
    EC2 → Select instance → Actions → Security → Modify IAM role
    → EC2-SSM-Role → Update

    Verify SSM Connectivity
    Systems Manager → Fleet Manager
    The instance should appear with status Online. 
    If it shows Connection Lost, restart the SSM agent on the instance.

    Install SSM Agent (if not already present)
    
    # Ubuntu
    sudo snap install amazon-ssm-agent --classic
    sudo snap start amazon-ssm-agent

### Task 2 — Install Ansible on the Control Node
    
    # Ubuntu / Debian
    sudo apt update
    sudo apt install -y ansible python3-pip
    ansible --version

### Task 3 — Configure AWS Credentials:

    aws configure
    # Enter: Access Key, Secret Key, region, output format
    
    # Or use environment variables
    export AWS_ACCESS_KEY_ID="your-access-key"
    export AWS_SECRET_ACCESS_KEY="your-secret-key"
    export AWS_DEFAULT_REGION="us-east-1"
    
    aws sts get-caller-identity

### Task 4 — Set Up the Lab Directory:

    mkdir ~/ansible-lab && cd ~/ansible-lab
    # Copy all files from this project into ~/ansible-lab/
    Tag your target EC2 instances so they appear in the web_servers group:
    EC2 → Instance → Tags → Add tag
      Key:   Role
      Value: web

    Verify the inventory discovers them:
    ansible-inventory --list

### Task 5 — Create IAM Role for Ansible Execution:

    IAM → Roles → Create role
    
      Trusted entity: AWS service → EC2 (or IAM user if running locally)
      Policies:
        - AmazonSSMFullAccess       (for SSM Run Command)
        - AmazonEC2ReadOnlyAccess   (for dynamic inventory)
    
      Role name: AnsibleSSMExecutionRole
    
    → Create role

### Task 6 — Run the Playbook:

    From the Control Node directly
    cd ~/ansible-lab
    ansible-playbook nginx_playbook.yml

    Via SSM Run Command (Console):

    Systems Manager → Run Command → Run command
    
      Document:    AWS-RunShellScript
      Commands:
        cd /home/ec2-user/ansible-lab
        ansible-playbook nginx_playbook.yml
    
      Targets: Choose instances manually → select your instance
    
    → Run

### Task 7 — Verify:

    SSM Session Manager
    Systems Manager → Session Manager → Start session
    → Select instance → Start session
    
    systemctl status nginx
    nginx -v
    curl localhost

### CloudWatch Logs:

    CloudWatch → Log groups → /aws/ssm/AWS-RunShellScript
    → Open your command's log stream to see Ansible output

### Key Concepts:

    Idempotency
    Ansible tasks are idempotent — running the playbook multiple times produces the same result without unintended side effects.
    
    Situation                   Ansible behaviour

    Nginx already installed     Skips the install task
    Service already running     Skips the start task
    Config file unchanged       Skips the copy task and does not restart Nginx
    Config file changed         Copies the file and triggers the handler to restart Nginx

### Handlers:

    Handlers are tasks that run at the end of a play, and only if they were notified by another task. 
    In this playbook, the restart nginx handler runs only when the config file copy task actually makes a change — not on every run.
    
### SSM vs SSH:

    SSM does not require port 22 to be open. The SSM Agent on the target instance maintains an outbound HTTPS connection to SSM.
    Ansible sends commands through this channel, which is more secure and avoids the need to manage SSH keys.

### Cleanup:

    # Delete SSM document if created
    aws ssm delete-document --name "RunAnsiblePlaybook"
    
    # Delete EventBridge rule if created
    aws events remove-targets --rule DailyAnsibleRun --ids "1"
    aws events delete-rule --name DailyAnsibleRun
    
    # Delete IAM roles
    aws iam detach-role-policy \
      --role-name AnsibleSSMExecutionRole \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMFullAccess
    aws iam detach-role-policy \
      --role-name AnsibleSSMExecutionRole \
      --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
    aws iam delete-role --role-name AnsibleSSMExecutionRole
    
    aws iam detach-role-policy \
      --role-name EC2-SSM-Role \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    aws iam delete-role --role-name EC2-SSM-Role
    
    # Remove local files
    rm -rf ~/ansible-lab/

### License:

    MIT License