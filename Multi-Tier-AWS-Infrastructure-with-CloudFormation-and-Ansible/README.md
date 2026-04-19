# Multi-Tier AWS Infrastructure with CloudFormation and Ansible:

    Overview
    This project provisions a three-tier AWS infrastructure using a CloudFormation template managed by Ansible. The stack creates dedicated security groups and EC2 instances for a web tier, application tier, and database tier. Ansible playbooks handle creation, updates, and deletion.
    Key highlights:
    
    Three-tier network isolation: web → app → database, each with scoped security group rules
    VPC ID and AMI ID are template parameters — no hardcoded values in the template
    amazon.aws.cloudformation module is idempotent — safe to run multiple times
    Update playbook changes EnvironmentType from dev to prod as a practical example
    All sensitive values replaced with placeholders — ready to commit to version control

## Architecture:

    Internet
        |
        | port 80, 443
        v
    WebServer-SG → WebServerInstance (t3.micro)
        |
        | port 8080 (WebServer-SG source only)
        v
    AppServer-SG → AppServerInstance (t3.micro)
        |
        | port 3306 (AppServer-SG source only)
        v
    DB-SG (database tier — no EC2 in this lab, security group ready)
    
    All resources in the same VPC (vpc-XXXXXXXXXXXXXXXXX)

## Project Structure:

    Multi-Tier-AWS-Infrastructure-with-CloudFormation-and-Ansible/
    |
    |-- ec2-template.yaml     # CloudFormation template — 3-tier infrastructure
    |-- deploy.yaml           # Ansible playbook — create the stack
    |-- update-temp.yaml      # Ansible playbook — update stack parameters
    |-- delete-stack.yaml     # Ansible playbook — delete the stack
    |
    |-- README.md

## Prerequisites:
    
    Requirement                 Check

    Ansible 2.x                 ansible --version
    AWS CLI                     aws sts get-caller-identity
    amazon.aws collection       ansible-galaxy collection list | grep amazon
    boto3                       python3 -c "import boto3; print(boto3.__version__)"
    
    Install if missing:
    
    sudo apt update -y
    sudo apt install ansible awscli python3-pip -y
    pip3 install boto3 botocore
    ansible-galaxy collection install amazon.aws

### Task 1 — Update Placeholder Values:

    Before running any playbook, update these values in all four files:
    
    Placeholder                      Replace with

    your-region                      Your AWS region (e.g. us-east-1)
    your-key-pair                    Your EC2 key pair name
    vpc-XXXXXXXXXXXXXXXXX            Your VPC ID
    ami-XXXXXXXXXXXXXXXXX            Ubuntu 22.04 AMI for your region

### Task 2 — Validate the Template:

    mkdir ~/cloudformation-lab && cd ~/cloudformation-lab
    # Copy all files here
    
    aws cloudformation validate-template \
      --template-body file://ec2-template.yaml \
      --region your-region
    
    # A successful response lists the Parameters — no output means an error

### Task 3 — Deploy the Stack:
    
    # Syntax check
    ansible-playbook deploy.yaml --syntax-check
    
    # Deploy
    ansible-playbook deploy.yaml -v
    
    Expected output:
    
    TASK [Create CloudFormation stack]
    changed: [localhost]
    
    TASK [Print web server public IP]
    ok: [localhost] => {
        "msg": "Web Server IP: x.x.x.x"
    }
    
    PLAY RECAP
    localhost : ok=3  changed=1  unreachable=0  failed=0

    Verify via CLI:
    
    aws cloudformation describe-stacks \
      --stack-name my-multi-tier-stack \
      --region your-region \
      --query 'Stacks[0].{Status:StackStatus,Outputs:Outputs}' \
      --output json
    
    aws cloudformation describe-stack-resources \
      --stack-name my-multi-tier-stack \
      --region your-region \
      --query 'StackResources[*].{Type:ResourceType,ID:PhysicalResourceId,Status:ResourceStatus}' \
      --output table

### Task 4 — Update the Stack:
    
    ansible-playbook update-temp.yaml -v
    # Changes EnvironmentType from dev to prod
    # CloudFormation generates a changeset and applies only the diff


### Key Concepts:

    CloudFormation Parameters
    Parameters allow the same template to be reused across environments without modification. 
    Values are passed at deploy time — through the console, CLI, or Ansible template_parameters.
    
    !Ref and !GetAtt
    
    Function                      Purpose
    !Ref ResourceName             Returns the resource ID or parameter value
    !GetAtt Resource.Attribute    Returns a specific attribute (e.g. PublicIp)
    !Ref 'AWS::StackName'         Returns the stack name (built-in pseudo parameter)
    
    
    Security group layering
    
    The three tiers are isolated by chaining security groups as sources rather than using IP ranges:
    
    AppServer-SG allows port 8080 only from WebServerSecurityGroup
    DB-SG allows port 3306 only from AppServerSecurityGroup
    
    This means the database is unreachable from the internet even if the web server is compromised.
    Idempotency with state: present
    Running deploy.yaml when the stack already exists and nothing has changed produces ok=3 changed=0. 
    Running update-temp.yaml when a parameter has changed triggers a CloudFormation changeset that modifies only the affected resources.


### Cleanup:

    ansible-playbook delete-stack.yaml
    
    Delete via AWS CLI
    aws cloudformation delete-stack \
      --stack-name my-multi-tier-stack \
      --region your-region
    
    aws cloudformation wait stack-delete-complete \
      --stack-name my-multi-tier-stack
    
    echo "Stack deleted"
    Remove local files
    rm -rf ~/cloudformation-lab

### License:

    MIT License


