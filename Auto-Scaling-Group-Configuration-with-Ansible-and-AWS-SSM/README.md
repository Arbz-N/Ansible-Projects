 Auto Scaling Group Configuration with Ansible and AWS SSM
 

    Overview
    This project integrates Ansible with AWS Auto Scaling Groups (ASG) to automatically configure new EC2 instances when they launch. A Launch Template with User Data ensures SSM Agent is running and tags are applied, which allows Ansible's dynamic EC2 inventory to discover the instances immediately. A Lifecycle Hook pauses new instances in Pending:Wait state until Ansible configuration completes.
    Key highlights:
    
    Dynamic EC2 inventory via amazon.aws.aws_ec2 — discovers instances by tag
    Environment=production and ManagedBy=Ansible tags used as inventory filters
    Lifecycle Hook holds new instances in Pending:Wait until Ansible finishes
    Scale-out and scale-in CloudWatch alarms trigger at CPU 70% and 30%
    SNS topic receives lifecycle hook notifications
    All playbooks use connection: community.aws.aws_ssm — no SSH required

Project Structure:

    Auto-Scaling-Group-Configuration-with-Ansible-and-AWS-SSM/
    |
    |-- ansible.cfg                           # Ansible config — inventory plugin, SSM
    |-- userdata.sh                           # Launch Template User Data script
    |
    |-- inventory/
    |   |-- hosts.aws_ec2.yml                 # Dynamic EC2 inventory by tag
    |
    |-- playbooks/
    |   |-- install_dependencies.yml          # Install Nginx and packages
    |   |-- configure_instances.yml           # Deploy index page and app config
    |   |-- complete_lifecycle.yml            # Complete ASG lifecycle hook
    |
    |-- README.md

Prerequisites:

    - ansible-control-node running with AnsibleControlRole IAM role
    - Ansible, boto3, amazon.aws and community.aws collections installed
    - AWS CLI configured
    - A VPC with at least two subnets in different Availability Zones

Architecture:

    CloudWatch Alarm (CPU > 70%)
            |
            v
    ASG Scale-Out → new EC2 instance (Pending:Wait)
            |
            | Lifecycle Hook pauses instance
            | SSM Agent registers with Fleet Manager
            v
    Ansible (control node)
      |-- install_dependencies.yml  → Nginx + packages
      |-- configure_instances.yml   → index page + /etc/app.env
      |-- complete_lifecycle.yml    → CONTINUE
            |
            v
    Instance enters InService → receives traffic
    
    CloudWatch Alarm (CPU < 30%)
            |
            v
    ASG Scale-In → instance terminated

Task 1 — Attach IAM Policies:

    Add to AnsibleControlRole:
    
        AutoScalingFullAccess — create and manage ASG
        AmazonEC2FullAccess — create Launch Template and Security Group
        AmazonSNSFullAccess — create SNS topic for lifecycle notifications
    
    Verify AnsibleTargetRole has:
    
        AmazonSSMManagedInstanceCore — allows ASG-launched instances to register with SSM

Task 2 — Create Launch Template:

    EC2 → Launch Templates → Create launch template
    
      Name:           ansible-asg-template
      AMI:            Ubuntu Server 22.04 LTS (your region's AMI ID)
      Instance type:  t2.micro
      IAM role:       AnsibleTargetRole
      Security group: ports 22 and 80 open
    
      Advanced Details → User Data:
        Paste the contents of userdata.sh

    Create Security Group via CLI:

    VPC_ID=$(aws ec2 describe-vpcs \
      --filters "Name=isDefault,Values=true" \
      --query 'Vpcs[0].VpcId' --output text)
    
    SG_ID=$(aws ec2 create-security-group \
      --group-name "asg-webserver-sg" \
      --description "ASG Web Server Security Group" \
      --vpc-id $VPC_ID \
      --query 'GroupId' --output text)
    
    aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws ec2 authorize-security-group-ingress \
      --group-id $SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

Task 3 — Create Auto Scaling Group:

      ┌──────────────────────────────────────────────────────────┐
      │  Step 1 — Choose Launch Template:                        │
      │    Name              : ansible-web-asg                   │
      │    Launch Template   : ansible-asg-template              │
      │    Version           : Latest (Default)                  │
      ├──────────────────────────────────────────────────────────┤
      │  Step 2 — Network:                                       │
      │    VPC               : Default VPC                       │
      │    Availability Zones: us-east-1a, us-east-1b (dono)     │
      │                        ↑ Multi-AZ = high availability    │
      ├──────────────────────────────────────────────────────────┤
      │  Step 3 — Group Size:                                    │
      │    Desired Capacity  : 2  Need 2 instance                │
      │    Minimum Capacity  : 1  Minimum always 1               │
      │    Maximum Capacity  : 5  Maximum 5                      │
      ├──────────────────────────────────────────────────────────┤
      │  Step 4 — Tags:                                          │
      │    Key: Environment, Value: production                   │
      │    Key: ManagedBy,   Value: Ansible                      │
      └──────────────────────────────────────────────────────────┘

Task 4 — Create Scaling Policies and CloudWatch Alarms:

    # Scale-out policy (add 1 instance)
    SCALE_OUT_ARN=$(aws autoscaling put-scaling-policy \
      --auto-scaling-group-name "ansible-web-asg" \
      --policy-name "scale-out-policy" \
      --policy-type "SimpleScaling" \
      --adjustment-type "ChangeInCapacity" \
      --scaling-adjustment 1 \
      --cooldown 300 \
      --query 'PolicyARN' --output text)
    
    # CPU high alarm — triggers scale-out
    aws cloudwatch put-metric-alarm \
      --alarm-name "cpu-high-alarm" \
      --metric-name CPUUtilization \
      --namespace AWS/EC2 \
      --statistic Average \
      --period 300 \
      --threshold 70 \
      --comparison-operator GreaterThanThreshold \
      --dimensions "Name=AutoScalingGroupName,Value=ansible-web-asg" \
      --evaluation-periods 2 \
      --alarm-actions $SCALE_OUT_ARN
    
    # Scale-in policy (remove 1 instance)
    SCALE_IN_ARN=$(aws autoscaling put-scaling-policy \
      --auto-scaling-group-name "ansible-web-asg" \
      --policy-name "scale-in-policy" \
      --policy-type "SimpleScaling" \
      --adjustment-type "ChangeInCapacity" \
      --scaling-adjustment -1 \
      --cooldown 300 \
      --query 'PolicyARN' --output text)
    
    # CPU low alarm — triggers scale-in
    aws cloudwatch put-metric-alarm \
      --alarm-name "cpu-low-alarm" \
      --metric-name CPUUtilization \
      --namespace AWS/EC2 \
      --statistic Average \
      --period 300 \
      --threshold 30 \
      --comparison-operator LessThanThreshold \
      --dimensions "Name=AutoScalingGroupName,Value=ansible-web-asg" \
      --evaluation-periods 2 \
      --alarm-actions $SCALE_IN_ARN

Task 5 — Create Lifecycle Hook:

    SNS_ARN=$(aws sns create-topic \
      --name "asg-lifecycle-topic" \
      --query 'TopicArn' --output text)
    
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    aws autoscaling put-lifecycle-hook \
      --lifecycle-hook-name "ansible-launch-hook" \
      --auto-scaling-group-name "ansible-web-asg" \
      --lifecycle-transition "autoscaling:EC2_INSTANCE_LAUNCHING" \
      --notification-target-arn $SNS_ARN \
      --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AnsibleControlRole" \
      --heartbeat-timeout 300 \
      --default-result "ABANDON"
    # ABANDON = if the hook times out without CONTINUE, instance is terminated

Task 6 — Set Up Ansible Project:

    mkdir -p ~/ansible-asg-lab/{inventory,playbooks}
    cd ~/ansible-asg-lab

    Copy all files from this project into ~/ansible-asg-lab/ maintaining the directory structure.
    Update placeholder values in inventory/hosts.aws_ec2.yml:
    
    your-region → your AWS region
    your-account-id → your 12-digit account ID

Task 7 — Run Playbooks:

    Verify ASG instances are registered in SSM

        aws ssm describe-instance-information \
          --query 'InstanceInformationList[].[InstanceId,PingStatus]' \
          --output table

    Install packages on all ASG instances:
    
        cd ~/ansible-asg-lab
            ansible-playbook playbooks/install_dependencies.yml
    
    Configure all instances
    
        ansible-playbook playbooks/configure_instances.yml

    Configure a specific new instance and complete its lifecycle hook
        
        NEW_INSTANCE_ID="i-XXXXXXXXXXXXXXXXX"
        
        ansible-playbook playbooks/install_dependencies.yml \
          --limit "$NEW_INSTANCE_ID"
        
        ansible-playbook playbooks/configure_instances.yml \
          --limit "$NEW_INSTANCE_ID"
        
        ansible-playbook playbooks/complete_lifecycle.yml \
          --extra-vars "target_instance_id=$NEW_INSTANCE_ID"

    Trigger manual scale-out for testing
    
    aws autoscaling set-desired-capacity \
      --auto-scaling-group-name "ansible-web-asg" \
      --desired-capacity 3

Task 8 — Verify:

    # ASG status
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names "ansible-web-asg" \
      --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:length(Instances)}' \
      --output table
    
    # Nginx running on all instances
    ansible all -m command -a "systemctl status nginx --no-pager"
    
    # Custom page served
    ansible all -m command -a "curl -s http://localhost"
    
    # Config file present
    ansible all -m command -a "cat /etc/app.env"

Key Concepts:

    Lifecycle Hook
    A lifecycle hook pauses a new instance in Pending:Wait state. 
    This gives Ansible time to install software and deploy configuration. 
    Only after complete_lifecycle.yml runs with CONTINUE does the instance enter InService and begin receiving traffic from the load balancer. 
    If the hook times out without a response, ABANDON terminates the instance.
    
    Dynamic inventory with propagated tags
    The PropagateAtLaunch=true flag on ASG tags ensures every new instance automatically receives Environment=production and ManagedBy=Ansible. 
    The Ansible inventory plugin uses these tags as filters — no manual updates needed when the ASG scales out.
    
    Cooldown period
    The --cooldown 300 on scaling policies prevents the ASG from immediately scaling again after an action. 
    Without it, a burst of CPU activity could trigger multiple scale-out events in rapid succession before the first new instance has time to absorb load.


Cleanup:

    # Delete ASG — terminates all running instances
    aws autoscaling delete-auto-scaling-group \
      --auto-scaling-group-name "ansible-web-asg" \
      --force-delete
    
    # Delete CloudWatch alarms
    aws cloudwatch delete-alarms \
      --alarm-names "cpu-high-alarm" "cpu-low-alarm"
    
    # Delete SNS topic
    aws sns delete-topic --topic-arn $SNS_ARN
    
    # Delete Launch Template
    aws ec2 delete-launch-template \
      --launch-template-name "ansible-asg-template"
    
    # Delete Security Group (after instances are terminated)
    aws ec2 delete-security-group --group-id $SG_ID
    
    # Remove local files
    rm -rf ~/ansible-asg-lab

    Terminate ansible-control-node via the EC2 console.

License:

    MIT License