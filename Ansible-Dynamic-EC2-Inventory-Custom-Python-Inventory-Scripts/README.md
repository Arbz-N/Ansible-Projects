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
