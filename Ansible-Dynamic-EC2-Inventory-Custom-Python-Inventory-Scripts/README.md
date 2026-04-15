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

