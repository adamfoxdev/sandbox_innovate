# Cost Optimization Guide

This guide provides detailed cost analysis, comparison tables, and optimization strategies for running AI sandbox environments across Azure, AWS, GCP, and local infrastructure.

---

## Table of Contents

- [Cost Comparison Tables](#cost-comparison-tables)
- [Spot & Preemptible Instance Strategy](#spot--preemptible-instance-strategy)
- [When Local Hardware Is Cheaper](#when-local-hardware-is-cheaper)
- [Storage Lifecycle Policies](#storage-lifecycle-policies)
- [Autoscaling and Shutdown Automation](#autoscaling-and-shutdown-automation)
- [Example Monthly Budgets](#example-monthly-budgets)
- [Cost Monitoring and Alerting](#cost-monitoring-and-alerting)
- [Cost Optimization Checklist](#cost-optimization-checklist)

---

## Cost Comparison Tables

### GPU Instance Cost Comparison (T4 — Entry GPU)

Comparable NVIDIA T4 GPU instances across all three clouds (us-east regions, 2024 pricing):

| Cloud | Instance | vCPUs | RAM | On-Demand/hr | 1-yr Reserved/hr | Spot/hr (approx) |
|-------|----------|-------|-----|-------------|-----------------|-----------------|
| AWS | g4dn.xlarge | 4 | 16 GB | $0.526 | $0.334 | $0.158–$0.210 |
| Azure | NC4as_T4_v3 | 4 | 28 GB | $0.526 | $0.316 | $0.079–$0.158 |
| GCP | n1-standard-4 + T4 | 4 | 15 GB | ~$0.750 | ~$0.488 | ~$0.225 |

> Azure provides more RAM (28 GB vs 16 GB for AWS) at the same price point.
> GCP is slightly more expensive on-demand but offers strong SUD discounts for always-on workloads.

### GPU Instance Cost Comparison (A10/A10G/L4 — Mid-tier GPU)

| Cloud | Instance | GPU | VRAM | On-Demand/hr | 1-yr Reserved/hr | Spot/hr (approx) |
|-------|----------|-----|------|-------------|-----------------|-----------------|
| AWS | g5.xlarge | A10G | 24 GB | $1.006 | $0.642 | $0.302–$0.402 |
| Azure | NV36ads_A10_v5 | A10 | 24 GB | $2.28 | $1.37 | $0.456 |
| GCP | g2-standard-8 | L4 | 24 GB | ~$0.890 | ~$0.578 | ~$0.267 |

> GCP G2 instances with L4 GPUs are the most cost-effective for 24 GB VRAM workloads.
> AWS G5 offers a good balance of price and availability.

### CPU-Only Instance Cost Comparison

| Cloud | Instance | vCPUs | RAM | On-Demand/hr | Best For |
|-------|----------|-------|-----|-------------|----------|
| AWS | c5.2xlarge | 8 | 16 GB | $0.340 | CPU inference |
| Azure | D4s_v5 | 4 | 16 GB | $0.192 | CPU inference |
| GCP | n2-standard-4 | 4 | 16 GB | $0.190 | CPU inference |

### Storage Cost Comparison (per GB/month)

| Storage Type | AWS | Azure | GCP |
|-------------|-----|-------|-----|
| Object storage (hot) | S3 Standard: $0.023 | Blob Hot LRS: $0.018 | GCS Standard: $0.020 |
| Object storage (cool) | S3 Intelligent-Tiering: $0.0125 | Blob Cool: $0.010 | GCS Nearline: $0.010 |
| Object storage (archive) | S3 Glacier: $0.004 | Blob Archive: $0.00099 | GCS Coldline: $0.004 |
| Block storage (SSD) | gp3: $0.08/GB | Premium SSD P10: $0.17/GB | pd-ssd: $0.17/GB |
| Shared file storage | EFS: $0.30/GB | Azure Files Prem: $0.21/GB | Filestore: $0.20/GB |

> Azure Blob Archive is the cheapest for long-term model weight storage at $0.001/GB/month.

### Data Egress Cost Comparison

| Transfer | AWS | Azure | GCP |
|---------|-----|-------|-----|
| Ingress | Free | Free | Free |
| Egress to internet (first 10 TB) | $0.09/GB | $0.087/GB | $0.085/GB |
| Cross-region (same cloud) | $0.02/GB | $0.02/GB | $0.01/GB |
| Via private endpoint (object storage) | Free (Gateway endpoint) | Free (Private endpoint) | Free (Private Google Access) |

> **Always use private/VPC endpoints for storage access** — eliminates data transfer costs.

---

## Spot & Preemptible Instance Strategy

### Decision Framework

```
Is your workload interruptible?
  └── Can it checkpoint and resume?
        └── YES → Strong candidate for Spot/Preemptible
        └── NO  → Use On-Demand or Reserved

Is response time < 30 minutes important?
  └── YES (interactive work) → On-Demand
  └── NO (batch job overnight) → Spot/Preemptible

Estimated savings vs risk:
  • Savings: 60–90% cost reduction
  • Risk: Interruption with 2-min (AWS) / 30-sec (GCP) / 30-sec (Azure) notice
```

### Interruption Rates by Instance

Historical interruption rates vary significantly by instance type and region. Generally:

| Instance Tier | Typical Interruption Rate | Recommendation |
|--------------|--------------------------|----------------|
| Small (g4dn.xlarge, NC4as_T4_v3) | 5–15% per hour | Good for batch jobs > 2 hours |
| Medium (g5.xlarge, NC8as_T4_v3) | 3–10% per hour | Good for most batch workloads |
| Large (p3.2xlarge, NC6s_v3) | 1–5% per hour | Very suitable for overnight training |

Check real-time interruption rates:
- AWS: [Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/)
- Azure: [Azure Spot VM pricing page](https://azure.microsoft.com/pricing/spot-advisor/)
- GCP: GCP Spot/Preemptible has ~5–8% average hourly interruption rate

### Checkpointing Best Practices

```python
# PyTorch training with checkpointing every N steps
import torch
import os
import signal

class CheckpointManager:
    def __init__(self, model, optimizer, checkpoint_dir="s3://sandbox/checkpoints/"):
        self.model = model
        self.optimizer = optimizer
        self.checkpoint_dir = checkpoint_dir
        # Register signal handler for cloud interruption
        signal.signal(signal.SIGUSR1, self._emergency_checkpoint)

    def save(self, step: int, loss: float):
        checkpoint = {
            'step': step,
            'model_state_dict': self.model.state_dict(),
            'optimizer_state_dict': self.optimizer.state_dict(),
            'loss': loss,
        }
        path = os.path.join(self.checkpoint_dir, f"checkpoint-step-{step}.pt")
        torch.save(checkpoint, path)
        print(f"Checkpoint saved at step {step} to {path}")

    def load_latest(self):
        # Load latest checkpoint from storage
        checkpoints = sorted([f for f in os.listdir(self.checkpoint_dir) if f.endswith('.pt')])
        if checkpoints:
            latest = os.path.join(self.checkpoint_dir, checkpoints[-1])
            checkpoint = torch.load(latest)
            self.model.load_state_dict(checkpoint['model_state_dict'])
            self.optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
            return checkpoint['step']
        return 0

    def _emergency_checkpoint(self, signum, frame):
        print("Interruption signal received! Saving emergency checkpoint...")
        self.save(step=-1, loss=float('nan'))
```

---

## When Local Hardware Is Cheaper

### Break-Even Analysis

Local hardware becomes cost-effective when:
1. A developer uses GPU compute > 4–6 hours/day consistently
2. The team size is small (1–3 people) sharing one machine
3. Model sizes consistently fit in local VRAM (≤ 24 GB)

### NVIDIA GPU Purchase vs Cloud Cost

| GPU | Purchase Price | Usable VRAM | Cloud Equivalent | Break-Even (vs Spot) |
|-----|---------------|-------------|-----------------|---------------------|
| RTX 4060 Ti | ~$400 | 16 GB | g4dn.xlarge | ~2,500 hours (~10 mo @ 8h/day) |
| RTX 4080 | ~$800 | 16 GB | g4dn.xlarge | ~5,000 hours (~2 years @ 8h/day) |
| RTX 4090 | ~$1,600 | 24 GB | g5.xlarge | ~5,000 hours (~2 years @ 8h/day) |
| RTX 4090 × 2 | ~$3,200 | 48 GB | g5.12xlarge | ~2,700 hours (< 1 year @ 8h/day) |

> **Rule of thumb**: If you run GPU workloads > 6 hours/day, 5 days/week, local hardware pays for itself within 1–2 years vs on-demand cloud. Vs spot, the break-even is 2–4 years.

### When Cloud Wins

- You need more than 24 GB VRAM (requires multiple local GPUs, which are expensive and power-hungry)
- Team of 5+ developers (cloud is cheaper than 5+ workstations)
- Compliance requires centralized logging and access control
- You need reproducibility across team members on different hardware
- You need to scale from 0 to 8× A100 overnight for a training run

---

## Storage Lifecycle Policies

### Model Weight Storage Strategy

```
Day 0–30: Standard/Hot tier (active experimentation)
  Cost: ~$0.023/GB/mo (AWS S3 Standard)

Day 31–90: Cool/Infrequent Access tier
  Cost: ~$0.0125/GB/mo (AWS S3-IA)
  Action: Move automatically via lifecycle rule

Day 91–365: Archive tier (if not tagged "keep")
  Cost: ~$0.004/GB/mo (AWS Glacier)

Day 365+: Delete (unless explicitly tagged "permanent")
```

### AWS S3 Lifecycle Policy

```json
{
  "Rules": [
    {
      "ID": "ModelWeightLifecycle",
      "Status": "Enabled",
      "Filter": {"Prefix": "models/"},
      "Transitions": [
        {"Days": 30, "StorageClass": "STANDARD_IA"},
        {"Days": 90, "StorageClass": "GLACIER"}
      ],
      "Expiration": {"Days": 365},
      "NoncurrentVersionExpiration": {"NoncurrentDays": 30}
    },
    {
      "ID": "ExperimentOutputLifecycle",
      "Status": "Enabled",
      "Filter": {"Prefix": "outputs/"},
      "Expiration": {"Days": 90}
    }
  ]
}
```

### Azure Blob Lifecycle Policy

```json
{
  "rules": [
    {
      "name": "modelWeightPolicy",
      "enabled": true,
      "type": "Lifecycle",
      "definition": {
        "filters": {"blobTypes": ["blockBlob"], "prefixMatch": ["models/"]},
        "actions": {
          "baseBlob": {
            "tierToCool": {"daysAfterModificationGreaterThan": 30},
            "tierToArchive": {"daysAfterModificationGreaterThan": 90},
            "delete": {"daysAfterModificationGreaterThan": 365}
          }
        }
      }
    }
  ]
}
```

---

## Autoscaling and Shutdown Automation

### Auto-Shutdown Implementation

#### Azure (Azure Automation)

```bash
# Enable auto-shutdown via CLI
az vm auto-shutdown \
  --resource-group rg-ai-sandbox \
  --name vm-ai-sandbox \
  --time 2000 \
  --email team@company.com
```

#### AWS (EventBridge + Lambda)

```python
# Lambda function to stop idle EC2 instances
import boto3
import json

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    cloudwatch = boto3.client('cloudwatch')

    # Get all sandbox instances
    instances = ec2.describe_instances(
        Filters=[
            {'Name': 'tag:Environment', 'Values': ['sandbox']},
            {'Name': 'instance-state-name', 'Values': ['running']}
        ]
    )

    for reservation in instances['Reservations']:
        for instance in reservation['Instances']:
            instance_id = instance['InstanceId']

            # Check average CPU utilization over last 30 minutes
            response = cloudwatch.get_metric_statistics(
                Namespace='AWS/EC2',
                MetricName='CPUUtilization',
                Dimensions=[{'Name': 'InstanceId', 'Value': instance_id}],
                StartTime=__import__('datetime').datetime.utcnow() - __import__('datetime').timedelta(minutes=30),
                EndTime=__import__('datetime').datetime.utcnow(),
                Period=1800,
                Statistics=['Average']
            )

            if response['Datapoints']:
                avg_cpu = response['Datapoints'][0]['Average']
                if avg_cpu < 5.0:  # Less than 5% CPU for 30 minutes
                    print(f"Stopping idle instance {instance_id} (CPU: {avg_cpu:.1f}%)")
                    ec2.stop_instances(InstanceIds=[instance_id])

    return {'statusCode': 200, 'body': 'Idle instance check complete'}
```

#### GCP (Cloud Scheduler + Cloud Functions)

```python
# Cloud Function to stop idle GCE instances
from googleapiclient import discovery
from google.cloud import monitoring_v3
import datetime

def stop_idle_instances(request):
    compute = discovery.build('compute', 'v1')
    monitoring = monitoring_v3.MetricServiceClient()

    project_id = "prj-ai-sandbox"
    zone = "us-central1-a"

    instances = compute.instances().list(project=project_id, zone=zone).execute()

    for instance in instances.get('items', []):
        if instance.get('status') != 'RUNNING':
            continue

        # Check if instance is tagged as sandbox
        labels = instance.get('labels', {})
        if labels.get('environment') != 'sandbox':
            continue

        # Query GPU utilization (requires DCGM exporter)
        # Simplified: check CPU utilization
        instance_name = instance['name']
        # ... metric query logic ...
        # Stop if idle

    return 'OK'
```

---

## Example Monthly Budgets

### Small Team (1–5 Developers)

**Scenario**: 5 developers, each using a GPU sandbox 4 hours/day on weekdays

| Item | Configuration | Monthly Cost |
|------|-------------|-------------|
| AWS g4dn.xlarge × 5 (spot) | 4h/day × 22 days × 5 × $0.16/hr | ~$70 |
| S3 storage (models + data) | 500 GB | ~$12 |
| Data transfer | ~50 GB egress | ~$5 |
| CloudWatch / logging | Standard | ~$5 |
| **Total** | | **~$92/month** |

**Alternative (local Docker, 0 cloud)**: $0/month (hardware already owned)

### Medium Team (6–20 Developers)

**Scenario**: 15 developers, shared GPU environments, business hours

| Item | Configuration | Monthly Cost |
|------|-------------|-------------|
| Azure NC8as_T4_v3 × 3 (shared) | 10h/day × 22 days × 3 × $0.75/hr | ~$495 |
| Azure Blob storage | 2 TB | ~$36 |
| Log Analytics workspace | 10 GB/day | ~$230 |
| Key Vault operations | ~100K ops | ~$3 |
| Azure Monitor | Metrics + alerts | ~$20 |
| **Total** | | **~$784/month** |

**With 1-yr Reserved Instances**: ~$470/month (40% savings)

### Large Team (20+ Developers)

**Scenario**: 30 developers, dedicated environments, some 24/7 inference servers

| Item | Configuration | Monthly Cost |
|------|-------------|-------------|
| GCP g2-standard-8 (L4) × 10 | 8h/day × 22 days × 10 × $0.89/hr | ~$1,565 |
| GCP n2-standard-4 × 5 (CPU) | Always-on × 5 × $0.19/hr | ~$695 |
| Cloud Storage | 5 TB | ~$100 |
| Cloud Logging / Monitoring | Full suite | ~$200 |
| Identity-Aware Proxy | Usage | ~$20 |
| **Total** | | **~$2,580/month** |

**With Spot VMs + CUD**: ~$1,200/month (53% savings)

---

## Cost Monitoring and Alerting

### Budget Alerts Setup

#### AWS

```bash
# Create budget alert at 80% of monthly budget
aws budgets create-budget \
  --account-id $ACCOUNT_ID \
  --budget '{
    "BudgetName": "ai-sandbox-monthly",
    "BudgetLimit": {"Amount": "500", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST",
    "CostFilters": {"TagKeyValue": ["user:Environment$sandbox"]}
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [{"SubscriptionType": "EMAIL", "Address": "team@company.com"}]
    }
  ]'
```

#### Azure

```bash
az consumption budget create \
  --budget-name ai-sandbox-budget \
  --amount 500 \
  --time-grain Monthly \
  --resource-group rg-ai-sandbox \
  --start-date $(date +%Y-%m-01) \
  --end-date 2025-12-31 \
  --notifications '[{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["team@company.com"],"thresholdType":"Percentage"}]'
```

---

## Cost Optimization Checklist

- [ ] Auto-shutdown configured (max 30 min idle before shutdown)
- [ ] Spot/preemptible instances used for all batch workloads
- [ ] Reserved instances purchased for always-on infrastructure (> 50% utilization)
- [ ] S3/Blob/GCS lifecycle policies configured (Cool after 30d, Archive after 90d)
- [ ] Budget alerts set at 50%, 80%, 100% of monthly budget
- [ ] Storage private endpoints enabled (eliminates egress costs)
- [ ] GPU utilization dashboards in place (detect idle paid instances)
- [ ] Right-sizing review performed monthly (scale down oversized instances)
- [ ] Dev/test workloads running only during business hours (scheduled start/stop)
- [ ] Model weights cached in private registry (avoid repeated HuggingFace downloads)
