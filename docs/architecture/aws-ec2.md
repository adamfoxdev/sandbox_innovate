# AWS EC2 Sandbox Guide

This guide covers AI sandbox environments on AWS EC2, including instance selection, cost optimization with Spot instances, VPC isolation, IAM security, and S3 data management.

---

## Table of Contents

- [Recommended Instance Types](#recommended-instance-types)
- [GPU vs CPU Tradeoffs](#gpu-vs-cpu-tradeoffs)
- [Cost Estimates](#cost-estimates)
- [VPC Isolation and Security Groups](#vpc-isolation-and-security-groups)
- [IAM Roles and Policies](#iam-roles-and-policies)
- [S3 and Data-Egress Considerations](#s3-and-data-egress-considerations)
- [Spot Instance Guidance](#spot-instance-guidance)
- [Recommended Configuration Summary](#recommended-configuration-summary)

---

## Recommended Instance Types

### G4 Series (NVIDIA T4 — Best Price/Performance for Inference)

| Instance | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|----------|-----|----------|-------|-----|-------------------|
| `g4dn.xlarge` | 1× NVIDIA T4 | 16 GB | 4 | 16 GB | ~$0.526 |
| `g4dn.2xlarge` | 1× NVIDIA T4 | 16 GB | 8 | 32 GB | ~$0.752 |
| `g4dn.4xlarge` | 1× NVIDIA T4 | 16 GB | 16 | 64 GB | ~$1.204 |
| `g4dn.8xlarge` | 1× NVIDIA T4 | 16 GB | 32 | 128 GB | ~$2.264 |
| `g4dn.12xlarge` | 4× NVIDIA T4 | 64 GB | 48 | 192 GB | ~$3.912 |

### G5 Series (NVIDIA A10G — Better for Larger Models)

| Instance | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|----------|-----|----------|-------|-----|-------------------|
| `g5.xlarge` | 1× NVIDIA A10G | 24 GB | 4 | 16 GB | ~$1.006 |
| `g5.2xlarge` | 1× NVIDIA A10G | 24 GB | 8 | 32 GB | ~$1.212 |
| `g5.4xlarge` | 1× NVIDIA A10G | 24 GB | 16 | 64 GB | ~$1.624 |
| `g5.12xlarge` | 4× NVIDIA A10G | 96 GB | 48 | 192 GB | ~$5.672 |
| `g5.48xlarge` | 8× NVIDIA A10G | 192 GB | 192 | 768 GB | ~$16.288 |

### P3 Series (NVIDIA V100 — Training-Optimized)

| Instance | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|----------|-----|----------|-------|-----|-------------------|
| `p3.2xlarge` | 1× NVIDIA V100 | 16 GB | 8 | 61 GB | ~$3.06 |
| `p3.8xlarge` | 4× NVIDIA V100 | 64 GB | 32 | 244 GB | ~$12.24 |
| `p3.16xlarge` | 8× NVIDIA V100 | 128 GB | 64 | 488 GB | ~$24.48 |

### P4 / P5 Series (NVIDIA A100 — Largest Models)

| Instance | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|----------|-----|----------|-------|-----|-------------------|
| `p4d.24xlarge` | 8× NVIDIA A100 | 320 GB | 96 | 1152 GB | ~$32.77 |
| `p5.48xlarge` | 8× NVIDIA H100 | 640 GB | 192 | 2048 GB | ~$98.32 |

### CPU-Only Options

| Instance | vCPUs | RAM | Hourly | Best For |
|----------|-------|-----|--------|----------|
| `c5.2xlarge` | 8 | 16 GB | ~$0.34 | GGUF/CPU inference |
| `c5.4xlarge` | 16 | 32 GB | ~$0.68 | Larger CPU inference |
| `m5.4xlarge` | 16 | 64 GB | ~$0.768 | Balanced, data processing |
| `r5.2xlarge` | 8 | 64 GB | ~$0.504 | Memory-intensive workloads |

---

## GPU vs CPU Tradeoffs

### When to Choose GPU on EC2

- Running inference on models > 3B parameters with < 5-second latency requirements
- Fine-tuning with QLoRA, LoRA, or full fine-tuning pipelines
- High-throughput serving with vLLM (PagedAttention requires GPU)
- Multimodal model experiments (LLaVA, BLIP, Flamingo)
- Embedding generation at scale (> 50,000 documents/hour)

### When CPU Is Sufficient on EC2

- API-first development targeting Azure OpenAI, Bedrock, or OpenAI endpoints
- Data preprocessing, cleaning, tokenization
- Testing agentic workflows and RAG pipelines with external model APIs
- Cost-constrained experimentation where latency is not critical

### GPU Instance Selection Guide

```
What model size are you working with?
  ≤ 7B parameters  → g4dn.xlarge (T4, 16 GB VRAM) — cheapest option
  7B–13B parameters → g5.xlarge (A10G, 24 GB VRAM) — better throughput
  13B–34B parameters → g5.2xlarge or g4dn.12xlarge (multi-T4)
  34B–70B parameters → g5.12xlarge (4× A10G, 96 GB VRAM)
  70B+ parameters   → p4d.24xlarge or multi-node setup
```

---

## Cost Estimates

All prices are **us-east-1 (N. Virginia)**, as of 2024. Use the [AWS Pricing Calculator](https://calculator.aws) for current rates.

### On-Demand vs Savings Plans

| Instance | On-Demand/hr | 1-yr Savings Plan/hr | 3-yr Savings Plan/hr |
|----------|-------------|---------------------|---------------------|
| `g4dn.xlarge` | $0.526 | ~$0.334 (~36% off) | ~$0.230 (~56% off) |
| `g5.xlarge` | $1.006 | ~$0.642 (~36% off) | ~$0.438 (~56% off) |
| `p3.2xlarge` | $3.060 | ~$1.989 (~35% off) | ~$1.319 (~57% off) |

### Monthly Cost Examples (Business Hours Usage)

| Scenario | Instance | Usage | Monthly Cost |
|----------|----------|-------|-------------|
| Solo developer | g4dn.xlarge | 8h/day, 20 days | ~$84 |
| Small team (shared) | g4dn.2xlarge | 10h/day, 22 days | ~$165 |
| Dedicated inference | g5.xlarge | 24/7 | ~$730 |
| Training experiments | p3.2xlarge | 4h/day, 10 days | ~$122 |

### Spot Instance Cost Examples

| Instance | On-Demand/hr | Typical Spot/hr | Savings |
|----------|-------------|----------------|---------|
| `g4dn.xlarge` | $0.526 | ~$0.157–$0.210 | 60–70% |
| `g5.xlarge` | $1.006 | ~$0.302–$0.402 | 60–70% |
| `g4dn.12xlarge` | $3.912 | ~$1.174–$1.565 | 60–70% |

---

## VPC Isolation and Security Groups

### Recommended VPC Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  VPC: vpc-ai-sandbox (10.0.0.0/16)                           │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  Private Subnet: subnet-sandbox (10.0.1.0/24)       │     │
│  │  AZ: us-east-1a                                     │     │
│  │                                                     │     │
│  │  ┌────────────────────────────────────────────┐     │     │
│  │  │  EC2: i-ai-sandbox (No public IP)           │     │     │
│  │  │  Security Group: sg-ai-sandbox              │     │     │
│  │  └────────────────────────────────────────────┘     │     │
│  └─────────────────────────────────────────────────────┘     │
│                                                              │
│  VPC Endpoints (Gateway):                                    │
│  ├── S3: vpce-s3 (free, for S3 access)                       │
│  └── DynamoDB: vpce-dynamodb (optional)                      │
│                                                              │
│  VPC Endpoints (Interface):                                  │
│  ├── Secrets Manager: vpce-secretsmanager                    │
│  ├── ECR: vpce-ecr-api, vpce-ecr-dkr                         │
│  └── SSM: vpce-ssm, vpce-ssmmessages, vpce-ec2messages        │
└──────────────────────────────────────────────────────────────┘
```

### Security Group Rules

**sg-ai-sandbox (attached to sandbox instance):**

Inbound Rules:

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| SSH | TCP | 22 | sg-bastion | From bastion host only |
| Custom TCP | TCP | 8888 | 10.0.0.0/8 | JupyterLab from VPN |
| Custom TCP | TCP | 11434 | 10.0.1.0/24 | Ollama API (intra-subnet) |

Outbound Rules:

| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| HTTPS | TCP | 443 | 0.0.0.0/0 | Package downloads (filtered via NACL or proxy) |
| All traffic | All | All | 10.0.0.0/16 | VPC internal communication |

### Network ACL (Additional Layer)

```
Inbound NACL:
Rule 100: Allow TCP 1024-65535 from 0.0.0.0/0  (return traffic)
Rule 200: Allow TCP 22 from 10.0.0.0/8          (SSH from VPN/bastion)
Rule *:   Deny all

Outbound NACL:
Rule 100: Allow TCP 443 to 0.0.0.0/0             (HTTPS)
Rule 200: Allow TCP 80  to 0.0.0.0/0             (HTTP — consider blocking)
Rule 300: Allow all to 10.0.0.0/16               (VPC internal)
Rule *:   Deny all
```

---

## IAM Roles and Policies

### Instance Profile Pattern

Every sandbox EC2 instance gets an **instance profile** with a dedicated IAM role. No long-lived access keys.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3SandboxBucket",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::sandbox-models-${account_id}",
        "arn:aws:s3:::sandbox-models-${account_id}/*"
      ]
    },
    {
      "Sid": "AllowSecretsManager",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:${account_id}:secret:sandbox/*"
    },
    {
      "Sid": "AllowECRRead",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowSSMSession",
      "Effect": "Allow",
      "Action": [
        "ssm:UpdateInstanceInformation",
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
        "ec2messages:AcknowledgeMessage",
        "ec2messages:DeleteMessage",
        "ec2messages:FailMessage",
        "ec2messages:GetEndpoint",
        "ec2messages:GetMessages",
        "ec2messages:SendReply"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AllowCloudWatch",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricData",
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

### Human Developer Access via AWS SSO

Configure AWS IAM Identity Center (SSO) with permission sets:

| Permission Set | Managed Policy / Inline | Purpose |
|---------------|------------------------|---------|
| `SandboxDeveloper` | Custom (EC2 start/stop, SSM connect, S3 read) | Regular developers |
| `SandboxAdmin` | PowerUserAccess (scoped to sandbox account) | Team leads |
| `SandboxViewer` | ReadOnlyAccess (scoped to sandbox account) | Auditors |

### Connecting via SSM (No SSH Port Required)

```bash
# Start SSM session (requires AWS CLI + session-manager-plugin)
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="bash"

# Port-forward JupyterLab
aws ssm start-session \
  --target i-0123456789abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters portNumber=8888,localPortNumber=8888
```

---

## S3 and Data-Egress Considerations

### Bucket Design

```
s3://sandbox-models-{account_id}/
  ├── huggingface/            # Cached HF model weights
  ├── ollama/                 # Ollama model blobs
  └── custom/                 # Fine-tuned models

s3://sandbox-datasets-{account_id}/
  ├── raw/                    # Original datasets
  ├── processed/              # Cleaned/preprocessed data
  └── outputs/                # Model outputs, generations

s3://sandbox-notebooks-{account_id}/
  └── {username}/             # Per-developer notebook storage
```

### S3 Security Configuration

```bash
# Block all public access
aws s3api put-public-access-block \
  --bucket sandbox-models-${ACCOUNT_ID} \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Enable versioning (protect against accidental deletion)
aws s3api put-bucket-versioning \
  --bucket sandbox-models-${ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Enable server-side encryption
aws s3api put-bucket-encryption \
  --bucket sandbox-models-${ACCOUNT_ID} \
  --server-side-encryption-configuration \
  '{"Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "aws:kms"}}]}'

# Lifecycle: move to Intelligent-Tiering after 30 days
aws s3api put-bucket-lifecycle-configuration \
  --bucket sandbox-models-${ACCOUNT_ID} \
  --lifecycle-configuration file://lifecycle.json
```

### Data Egress Costs

| Transfer Type | Cost |
|--------------|------|
| Data into S3 | Free |
| S3 to EC2 (same region, via VPC endpoint) | Free |
| S3 to EC2 (same region, via internet) | $0.09/GB |
| EC2 to internet (first 100 GB/mo) | $0.09/GB |
| EC2 to internet (next 9.9 TB) | $0.085/GB |

**Best practice**: Always use the S3 Gateway VPC Endpoint (free) to avoid data transfer charges.

---

## Spot Instance Guidance

### When to Use Spot

| Workload Type | Use Spot? | Rationale |
|--------------|-----------|-----------|
| Interactive JupyterLab session | No | Interruption breaks workflow |
| Batch inference (CSV → outputs) | Yes | Can checkpoint and resume |
| Model fine-tuning with checkpointing | Yes | Save checkpoint every 10 min |
| Overnight training runs | Yes | High savings, low interruption risk |
| CI/CD model evaluation | Yes | Stateless, can retry |

### Spot Interruption Handling

1. **Enable interruption notice handler** via the EC2 instance metadata service:

   ```bash
   #!/bin/bash
   # /usr/local/bin/spot-interrupt-handler.sh
   TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
   ACTION=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null)
   if echo "$ACTION" | grep -q "terminate"; then
     echo "Spot interruption detected! Saving checkpoint..."
     # Trigger checkpoint save in your training script
     pkill -SIGUSR1 python
   fi
   ```

2. **Checkpoint strategy**: Save model checkpoint to S3 every N steps; the training script reads the latest checkpoint on startup.

3. **AWS Spot Interruption Monitor**: Use AWS EventBridge rule to trigger Lambda on `EC2 Spot Instance Interruption Warning` event.

### Requesting Spot with Capacity Diversification

Use the `capacity-optimized` allocation strategy for best availability:

```bash
aws ec2 run-instances \
  --instance-type g4dn.xlarge \
  --image-id ami-0abcdef1234567890 \
  --instance-market-options '{"MarketType":"spot","SpotOptions":{"SpotInstanceType":"one-time","InstanceInterruptionBehavior":"terminate"}}' \
  --count 1 \
  --subnet-id subnet-0123456789abcdef0 \
  --security-group-ids sg-0123456789abcdef0 \
  --iam-instance-profile Name=ai-sandbox-instance-profile \
  --key-name sandbox-key
```

---

## Recommended Configuration Summary

| Parameter | Recommended Value |
|-----------|------------------|
| Instance Type | `g4dn.xlarge` (start); scale to `g5.xlarge` for larger models |
| AMI | AWS Deep Learning AMI (Ubuntu 22.04) |
| Root Volume | gp3, 100 GB |
| Data Volume | gp3, 500 GB (models + datasets) |
| Public IP | None |
| Network | Private subnet + Security Group + VPC Endpoints |
| Access | SSM Session Manager (no SSH port open) |
| Identity | EC2 Instance Profile (IAM Role) |
| Spot | Yes for batch jobs, No for interactive sessions |
| S3 | Versioned, encrypted, VPC endpoint, lifecycle policies |
| Monitoring | CloudWatch Agent + CloudTrail + GuardDuty |
| Auto-shutdown | EventBridge + Lambda on idle CPU/GPU threshold |
