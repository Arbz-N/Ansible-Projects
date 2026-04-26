#  S3 File Management with Ansible and amazon.aws:
 
    Overview
    This project demonstrates managing AWS S3 objects using Ansible and the amazon.aws.s3_object module. 
    Files are uploaded to an S3 bucket via the AWS CLI, 
    then downloaded to the control node using two Ansible playbooks — one for a specific list of files and one for the entire bucket.
    Key highlights:
    
    All playbooks run on localhost with connection: local — no target EC2 instance required
    amazon.aws.s3_object with mode: get downloads individual files
    amazon.aws.s3_object with mode: list retrieves all object keys from a bucket
    Loop over s3_contents.s3_keys to download every file in one task
    Idempotent — running the playbook again when files are unchanged reports ok not changed
    Sample files provided in sample-files/ ready to upload to S3

## Project Structure:

    S3-File-Management-with-Ansible-and-amazon/
    |
    |-- ansible.cfg                        # Ansible configuration — localhost inventory
    |-- download_from_s3.yml               # Download specific files by key
    |-- download_all_from_s3.yml           # List bucket and download everything
    |
    |-- sample-files/
    |   |-- configs/app.conf               # Sample config file to upload
    |   |-- scripts/deploy.sh              # Sample deploy script to upload
    |   |-- data/sample.txt                # Sample data file to upload
    |
    |-- README.md

## Prerequisites:

    Requirement                   Check
    
    Ansible 2.x                   ansible --version
    AWS CLI                       aws sts get-caller-identity
    amazon.aws collection         ansible-galaxy collection install amazon.aws
    boto3                         python3 -c "import boto3; print(boto3.__version__)"
    AmazonS3FullAccess            Attached to the IAM role on the control node

## Architecture:

    ansible-control-node
            |
            | connection: local
            | boto3 → AWS API
            v
    AWS S3 Bucket (my-ansible-lab-ACCOUNTID)
      |-- configs/app.conf
      |-- scripts/deploy.sh
      |-- data/sample.txt
            |
            | amazon.aws.s3_object mode: get
            v
    /tmp/downloads/
      |-- app.conf
      |-- deploy.sh
      |-- sample.txt

### Task 1 — Attach S3 Policy to IAM Role:

    aws iam attach-role-policy \
      --role-name AnsibleControlRole \
      --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess
    
    # Verify
    aws s3 ls
    # No error = access confirmed

### Task 2 — Create S3 Bucket and Upload Files:

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    BUCKET_NAME="my-ansible-lab-${ACCOUNT_ID}"
    
    aws s3 mb s3://$BUCKET_NAME --region your-region
    
    # Upload the sample files
    aws s3 cp sample-files/configs/app.conf   s3://$BUCKET_NAME/configs/app.conf
    aws s3 cp sample-files/scripts/deploy.sh  s3://$BUCKET_NAME/scripts/deploy.sh
    aws s3 cp sample-files/data/sample.txt    s3://$BUCKET_NAME/data/sample.txt
    
    # Verify
    aws s3 ls s3://$BUCKET_NAME --recursive

### Task 3 — Update Playbook Variables:

    Open both playbooks and update:
    
    s3_bucket_name → your actual bucket name (e.g. my-ansible-lab-123456789012)
    aws_region → your actual region
    
    Or use sed to replace automatically:
    sed -i "s/your-bucket-name/${BUCKET_NAME}/" download_from_s3.yml
    sed -i "s/your-bucket-name/${BUCKET_NAME}/" download_all_from_s3.yml
    sed -i "s/your-region/us-east-1/" download_from_s3.yml
    sed -i "s/your-region/us-east-1/" download_all_from_s3.yml

### Task 4 — Run the Playbooks:

    Download specific files
    bash# Syntax check
    ansible-playbook download_from_s3.yml --syntax-check

    # Run
    ansible-playbook download_from_s3.yml

    Expected output:
    TASK [Download files from S3]
    changed: [localhost] => (item=app.conf)
    changed: [localhost] => (item=deploy.sh)
    changed: [localhost] => (item=sample.txt)

    TASK [Show downloaded files]
    msg:
      - total 12K
        - -rw-r--r-- 1 root root 89 app.conf
        - -rw-r--r-- 1 root root 45 deploy.sh
        - -rw-r--r-- 1 root root 67 sample.txt

    Download entire bucket
    ansible-playbook download_all_from_s3.yml

    Verify locally
    ls -lh /tmp/downloads/
    cat /tmp/downloads/app.conf
    cat /tmp/downloads/sample.txt

    Task 5 — Idempotency Test
    # Run the playbook again — files already exist locally
    ansible-playbook download_from_s3.yml
    
    # The download tasks should report ok instead of changed
    # No files are re-downloaded when they are already present and unchanged

### Key Concepts:

    mode: get vs mode: list

    Mode         Purpose
    get          Download a single object to a local path
    list         Return a list of all object keys in the bucket
    put          Upload a local file to S3
    delete       Remove an object from S3

    connection: local
    Setting connection: local tells Ansible to run all tasks directly on the control node using the local Python environment. 
    Combined with hosts: localhost, the playbook makes AWS API calls through boto3 without any SSH connection or target EC2 instance.
    
    Dynamic download with mode: list
    The download_all_from_s3.yml playbook first calls mode: list to retrieve all object keys, 
    stores them in s3_contents.s3_keys, then loops over that list to download every object. 
    This means no manual updates are needed when new files are added to the bucket.

### Cleanup:

    # Delete all S3 objects then the bucket
    aws s3 rm s3://$BUCKET_NAME --recursive
    aws s3 rb s3://$BUCKET_NAME
    
    # Verify bucket is gone
    aws s3 ls | grep ansible-lab
    
    # Remove local downloaded files
    rm -rf /tmp/downloads/
    rm -rf /tmp/s3-full-download/
    rm -rf /tmp/s3-upload/
    rm -rf ~/ansible-s3-lab/
    Terminate ansible-control-node via the EC2 console.

### License:

    MIT License