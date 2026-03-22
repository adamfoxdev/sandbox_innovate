# AWS EC2 Sandbox Setup Guide

Step-by-step instructions for provisioning a secure AWS EC2 AI sandbox using CLI, CloudFormation, and Terraform.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [CLI Setup](#cli-setup)
- [CloudFormation Setup](#cloudformation-setup)
- [Terraform IaC Setup (Recommended)](#terraform-iac-setup-recommended)
- [Network and Identity Configuration](#network-and-identity-configuration)
- [Hardening Steps](#hardening-steps)
- [Validation Tests](#validation-tests)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **AWS CLI** v2 installed and configured:

   ```bash
   # Install AWS CLI v2
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip && sudo ./aws/install

   # Configure credentials
   aws configure
   # Or use SSO:
   aws configure sso

   # Verify
   aws sts get-caller-identity
   ```

2. **Session Manager Plugin** (for SSM-based SSH):

   ```bash
   curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o "session-manager-plugin.deb"
   sudo dpkg -i session-manager-plugin.deb
   ```

3. **Terraform** >= 1.5.0 (see [Azure VM Setup](azure-vm-setup.md) for installation).

4. **Required IAM permissions**:
   - `ec2:*` on sandbox VPC/subnet scope
   - `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:CreateInstanceProfile`
   - `s3:CreateBucket`, `s3:PutBucketPolicy`
   - `secretsmanager:CreateSecret`

5. **GPU quota check**:

   ```bash
   # Check g4dn instance limits in your account
   aws service-quotas get-service-quota \
     --service-code ec2 \
     --quota-code L-DB2E81BA \
     --region us-east-1
   # L-DB2E81BA = Running On-Demand G and VT instances
   ```

---

## CLI Setup

### Step 1: Create VPC

```bash
REGION="us-east-1"
TEAM_NAME="yourteam"

# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=vpc-ai-sandbox},{Key=Environment,Value=sandbox},{Key=Team,Value=$TEAM_NAME}]" \
  --query 'Vpc.VpcId' -o text)

echo "VPC ID: $VPC_ID"

# Enable DNS hostnames (needed for VPC endpoints)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
```

### Step 2: Create Private Subnet

```bash
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=subnet-sandbox-private},{Key=Environment,Value=sandbox}]" \
  --query 'Subnet.SubnetId' -o text)

echo "Subnet ID: $SUBNET_ID"
```

### Step 3: Create VPC Endpoints

```bash
# S3 Gateway Endpoint (free — eliminates data transfer costs)
aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --vpc-endpoint-type Gateway \
  --service-name com.amazonaws.$REGION.s3 \
  --route-table-ids $(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query 'RouteTables[0].RouteTableId' -o text)

# SSM Interface Endpoints (required for Session Manager without internet)
for SERVICE in ssm ssmmessages ec2messages; do
  aws ec2 create-vpc-endpoint \
    --vpc-id $VPC_ID \
    --vpc-endpoint-type Interface \
    --service-name com.amazonaws.$REGION.$SERVICE \
    --subnet-ids $SUBNET_ID \
    --security-group-ids $SG_ID \
    --private-dns-enabled
done
```

### Step 4: Create Security Group

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name sg-ai-sandbox \
  --description "Security group for AI sandbox instances" \
  --vpc-id $VPC_ID \
  --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=sg-ai-sandbox}]" \
  --query 'GroupId' -o text)

# Allow inbound from within VPC only
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8888 \
  --cidr 10.0.0.0/8 \
  --tag-specifications "ResourceType=security-group-rule,Tags=[{Key=Name,Value=JupyterLab-from-VPN}]"

# Remove default outbound all rule and replace with controlled rules
# (Optional — default allows all outbound, which is acceptable for most sandboxes)
```

### Step 5: Create IAM Role and Instance Profile

```bash
# Create trust policy
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name ai-sandbox-instance-role \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --tags Key=Environment,Value=sandbox

# Attach SSM policy (for Session Manager access)
aws iam attach-role-policy \
  --role-name ai-sandbox-instance-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

# Attach CloudWatch agent policy
aws iam attach-role-policy \
  --role-name ai-sandbox-instance-role \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name ai-sandbox-instance-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name ai-sandbox-instance-profile \
  --role-name ai-sandbox-instance-role
```

### Step 6: Create S3 Bucket

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account -o text)
BUCKET_NAME="sandbox-models-${ACCOUNT_ID}"

aws s3api create-bucket \
  --bucket $BUCKET_NAME \
  --region $REGION

# Block public access
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket $BUCKET_NAME \
  --server-side-encryption-configuration '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]}'

# Grant access to instance role
aws iam put-role-policy \
  --role-name ai-sandbox-instance-role \
  --policy-name S3SandboxAccess \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Action\": [\"s3:GetObject\",\"s3:PutObject\",\"s3:ListBucket\",\"s3:DeleteObject\"],
      \"Resource\": [\"arn:aws:s3:::${BUCKET_NAME}\",\"arn:aws:s3:::${BUCKET_NAME}/*\"]
    }]
  }"
```

### Step 7: Launch EC2 Instance

```bash
# Find the latest Deep Learning AMI (Ubuntu 22.04)
AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=Deep Learning AMI GPU PyTorch * (Ubuntu 22.04) *" \
            "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' -o text)

echo "Using AMI: $AMI_ID"

# Launch instance
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type g4dn.xlarge \
  --subnet-id $SUBNET_ID \
  --security-group-ids $SG_ID \
  --iam-instance-profile Name=ai-sandbox-instance-profile \
  --no-associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":100,"VolumeType":"gp3","Encrypted":true}},{"DeviceName":"/dev/sdb","Ebs":{"VolumeSize":500,"VolumeType":"gp3","Encrypted":true,"DeleteOnTermination":false}}]' \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=vm-ai-sandbox},{Key=Environment,Value=sandbox},{Key=Team,Value=$TEAM_NAME}]" \
  --user-data '#!/bin/bash
    # Install docker if not present
    which docker || curl -fsSL https://get.docker.com | bash
    # Format and mount data volume
    mkfs.xfs /dev/sdb && mkdir -p /data && echo "/dev/sdb /data xfs defaults 0 2" >> /etc/fstab && mount -a
  ' \
  --query 'Instances[0].InstanceId' -o text)

echo "Instance ID: $INSTANCE_ID"
```

---

## CloudFormation Setup

Use the provided CloudFormation template for a declarative setup:

```bash
aws cloudformation create-stack \
  --stack-name ai-sandbox-stack \
  --template-body file://templates/aws-ec2/cloudformation.yaml \
  --parameters \
    ParameterKey=TeamName,ParameterValue=yourteam \
    ParameterKey=InstanceType,ParameterValue=g4dn.xlarge \
    ParameterKey=VpcCidr,ParameterValue=10.0.0.0/16 \
  --capabilities CAPABILITY_IAM \
  --region $REGION

# Monitor stack creation
aws cloudformation wait stack-create-complete \
  --stack-name ai-sandbox-stack

# Get outputs
aws cloudformation describe-stacks \
  --stack-name ai-sandbox-stack \
  --query 'Stacks[0].Outputs' -o table
```

---

## Terraform IaC Setup (Recommended)

```bash
cd templates/aws-ec2

# Initialize
terraform init

# Configure variables
cat > terraform.tfvars << EOF
region        = "us-east-1"
instance_type = "g4dn.xlarge"
team_name     = "yourteam"
EOF

# Plan and apply
terraform plan -out=tfplan
terraform apply tfplan
```

---

## Hardening Steps

### 1. Enable GuardDuty

```bash
aws guardduty create-detector \
  --enable \
  --finding-publishing-frequency FIFTEEN_MINUTES \
  --region $REGION
```

### 2. Enable CloudTrail

```bash
aws cloudtrail create-trail \
  --name sandbox-audit-trail \
  --s3-bucket-name $BUCKET_NAME \
  --s3-key-prefix cloudtrail \
  --include-global-service-events \
  --is-multi-region-trail \
  --enable-log-file-validation

aws cloudtrail start-logging --name sandbox-audit-trail
```

### 3. Enable AWS Config

```bash
aws configservice put-configuration-recorder \
  --configuration-recorder name=sandbox-config,roleARN=arn:aws:iam::${ACCOUNT_ID}:role/config-role \
  --recording-group allSupported=true,includeGlobalResourceTypes=true
```

### 4. OS Hardening (on the instance via SSM)

```bash
# Connect via SSM
aws ssm start-session --target $INSTANCE_ID

# On the instance:
sudo apt update && sudo apt upgrade -y
sudo apt install -y fail2ban auditd unattended-upgrades

# Configure automatic security updates
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Enable auditd
sudo systemctl enable --now auditd

# Verify GPU driver
nvidia-smi
```

---

## Validation Tests

```bash
# 1. Verify no public IP
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].PublicIpAddress' -o text)
[ "$PUBLIC_IP" = "None" ] && echo "✅ No public IP" || echo "❌ Public IP: $PUBLIC_IP"

# 2. Verify SSM connectivity
aws ssm describe-instance-information \
  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
  --query 'InstanceInformationList[0].PingStatus' -o text
# Expected: Online

# 3. Verify IAM role attached
ROLE=$(aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' -o text)
echo "IAM Profile: $ROLE"
[ -n "$ROLE" ] && echo "✅ IAM role attached" || echo "❌ No IAM role"

# 4. Verify S3 access from instance
aws ssm start-session --target $INSTANCE_ID \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["aws s3 ls s3://'"$BUCKET_NAME"'"]'

# 5. Verify GPU (from instance)
aws ssm start-session --target $INSTANCE_ID \
  --document-name AWS-StartInteractiveCommand \
  --parameters 'command=["nvidia-smi"]'
```

---

## Troubleshooting

### Issue: SSM Session Manager connection fails

**Solutions**:
1. Ensure IAM role has `AmazonSSMManagedInstanceCore` policy attached
2. Verify SSM VPC endpoints are created (required if no internet access)
3. Check instance is running: `aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name'`
4. Wait 5–10 minutes after launch for SSM agent to register

### Issue: GPU instance quota exceeded

**Solutions**:
1. Request quota increase: AWS Console → Service Quotas → EC2 → G and VT instances
2. Try a different Availability Zone (quotas are regional but capacity can vary by AZ)
3. Use Spot Instance (often has more available capacity): add `--instance-market-options '{"MarketType":"spot"}'`

### Issue: S3 access denied from instance

**Solutions**:
1. Verify instance profile is attached
2. Check S3 bucket policy doesn't explicitly deny the instance role
3. Verify VPC S3 endpoint is created and route table is updated
4. Test with: `aws s3 ls s3://$BUCKET_NAME --debug 2>&1 | grep endpoint`

### Issue: CloudFormation stack rollback

**Solutions**:
```bash
# View stack events to find failure reason
aws cloudformation describe-stack-events \
  --stack-name ai-sandbox-stack \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
  --output table

# Common causes:
# - IAM permissions insufficient → check your user/role permissions
# - GPU quota exceeded → request quota increase
# - AZ doesn't support instance type → change AZ parameter
```
