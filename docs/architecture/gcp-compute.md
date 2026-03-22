# GCP Compute Engine Sandbox Guide

This guide covers AI sandbox environments on Google Cloud Platform Compute Engine, including machine type selection, GPU configuration, cost optimization with preemptible VMs, VPC isolation, and IAM security.

---

## Table of Contents

- [Recommended Machine Types](#recommended-machine-types)
- [GPU vs CPU Tradeoffs](#gpu-vs-cpu-tradeoffs)
- [Cost Estimates](#cost-estimates)
- [VPC Network Isolation](#vpc-network-isolation)
- [IAM and Service Accounts](#iam-and-service-accounts)
- [Cloud Storage Considerations](#cloud-storage-considerations)
- [Preemptible VM Guidance](#preemptible-vm-guidance)
- [Recommended Configuration Summary](#recommended-configuration-summary)

---

## Recommended Machine Types

GCP uses a **machine type + GPU accelerator** model, giving you flexibility to attach different GPUs to standard machine types.

### A2 Series (NVIDIA A100 — Highest Performance)

| Machine Type | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|-------------|-----|----------|-------|-----|-------------------|
| `a2-highgpu-1g` | 1× NVIDIA A100 | 40 GB | 12 | 85 GB | ~$3.67 |
| `a2-highgpu-2g` | 2× NVIDIA A100 | 80 GB | 24 | 170 GB | ~$7.34 |
| `a2-highgpu-4g` | 4× NVIDIA A100 | 160 GB | 48 | 340 GB | ~$14.68 |
| `a2-highgpu-8g` | 8× NVIDIA A100 | 320 GB | 96 | 680 GB | ~$29.37 |
| `a2-megagpu-16g` | 16× NVIDIA A100 | 640 GB | 96 | 1360 GB | ~$55.74 |
| `a2-ultragpu-1g` | 1× NVIDIA A100 80GB | 80 GB | 12 | 170 GB | ~$5.07 |

### N1 + GPU Attachment (Flexible — Best for Sandboxes)

Attach T4 or V100 GPUs to N1 custom/predefined machine types:

| Configuration | GPU | GPU VRAM | vCPUs | RAM | Approx Hourly |
|--------------|-----|----------|-------|-----|--------------|
| `n1-standard-4` + 1× T4 | NVIDIA T4 | 16 GB | 4 | 15 GB | ~$0.75 |
| `n1-standard-8` + 1× T4 | NVIDIA T4 | 16 GB | 8 | 30 GB | ~$1.00 |
| `n1-standard-4` + 1× V100 | NVIDIA V100 | 16 GB | 4 | 15 GB | ~$2.48 |
| `n1-standard-8` + 1× V100 | NVIDIA V100 | 16 GB | 8 | 30 GB | ~$2.75 |
| `n1-standard-4` + 2× T4 | 2× NVIDIA T4 | 32 GB | 4 | 15 GB | ~$1.50 |

### G2 Series (NVIDIA L4 — Efficient Inference)

| Machine Type | GPU | GPU VRAM | vCPUs | RAM | Hourly (On-Demand) |
|-------------|-----|----------|-------|-----|-------------------|
| `g2-standard-4` | 1× NVIDIA L4 | 24 GB | 4 | 16 GB | ~$0.70 |
| `g2-standard-8` | 1× NVIDIA L4 | 24 GB | 8 | 32 GB | ~$0.89 |
| `g2-standard-16` | 1× NVIDIA L4 | 24 GB | 16 | 64 GB | ~$1.35 |
| `g2-standard-48` | 4× NVIDIA L4 | 96 GB | 48 | 192 GB | ~$3.80 |

### CPU-Only Options

| Machine Type | vCPUs | RAM | Hourly | Best For |
|-------------|-------|-----|--------|----------|
| `n2-standard-4` | 4 | 16 GB | ~$0.19 | GGUF/CPU inference |
| `n2-standard-8` | 8 | 32 GB | ~$0.38 | Larger CPU models |
| `c3-standard-4` | 4 | 16 GB | ~$0.21 | Compute-intensive preprocessing |
| `m3-ultramem-32` | 32 | 976 GB | ~$7.50 | Memory-intensive (very large models, CPU) |

---

## GPU vs CPU Tradeoffs

### When to Choose GPU on GCP

- Running inference with models that need < 5-second response times
- Fine-tuning or QLoRA on any model > 3B parameters
- Using Vertex AI pipelines alongside your sandbox (A100 instances align with Vertex)
- High-throughput batch inference jobs overnight

### When CPU Is Sufficient on GCP

- Prototyping pipelines against Vertex AI endpoints or Google Gemini API
- Data preprocessing, feature engineering, embedding with remote APIs
- Lightweight experimentation with quantized small models (< 3B)
- Budget-constrained teams just starting AI exploration

### GPU Selection Guide for GCP

```
Use case → Recommended GPU:
  • Inference only, 7B–13B models  → NVIDIA T4 (n1-standard-8 + T4)
  • Inference, 13B–30B models       → NVIDIA L4 (g2-standard-16)
  • Fine-tuning / QLoRA 7B–13B      → NVIDIA V100 or L4
  • Large model inference 30B–70B   → NVIDIA A100 40GB (a2-highgpu-1g)
  • Full fine-tuning 13B+            → NVIDIA A100 (multi-GPU a2-highgpu-2g+)
```

---

## Cost Estimates

All prices are **us-central1 (Iowa)** region, as of 2024. Use [GCP Pricing Calculator](https://cloud.google.com/products/calculator) for current rates.

### On-Demand Pricing

| Configuration | Hourly | 8h/day (20 days) | Full Month |
|--------------|--------|-----------------|-----------|
| n1-standard-4 + 1× T4 | ~$0.75 | ~$120 | ~$548 |
| n1-standard-8 + 1× T4 | ~$1.00 | ~$160 | ~$730 |
| g2-standard-8 (L4) | ~$0.89 | ~$142 | ~$650 |
| a2-highgpu-1g (A100) | ~$3.67 | ~$587 | ~$2,679 |
| n2-standard-4 (CPU) | ~$0.19 | ~$30 | ~$139 |

### Committed Use Discounts (CUD)

GCP offers automatic sustained use discounts (SUD) for VMs running > 25% of the month:

| Usage % | Discount |
|---------|----------|
| 25–50% | ~10% |
| 50–75% | ~20% |
| 75–100% | ~30% |

1-year committed use contracts provide up to **37% discount**; 3-year up to **55% discount**.

### Preemptible VM Savings

| Configuration | On-Demand/hr | Preemptible/hr | Savings |
|--------------|-------------|---------------|---------|
| n1-standard-4 + T4 | ~$0.75 | ~$0.23 | ~70% |
| n1-standard-8 + T4 | ~$1.00 | ~$0.31 | ~69% |
| a2-highgpu-1g | ~$3.67 | ~$1.10 | ~70% |

---

## VPC Network Isolation

### Recommended VPC Architecture

```
┌────────────────────────────────────────────────────────────┐
│  GCP Project: prj-ai-sandbox                               │
│                                                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  VPC Network: vpc-ai-sandbox (custom mode)           │  │
│  │                                                      │  │
│  │  ┌───────────────────────────────────────────────┐   │  │
│  │  │  Subnet: subnet-sandbox-us-central1            │   │  │
│  │  │  IP range: 10.0.1.0/24                         │   │  │
│  │  │  Private Google Access: Enabled                │   │  │
│  │  │                                               │   │  │
│  │  │  ┌────────────────────────────────────────┐   │   │  │
│  │  │  │  Compute Instance: vm-ai-sandbox        │   │   │  │
│  │  │  │  No external IP                        │   │   │  │
│  │  │  │  Service Account: sa-sandbox@prj.iam   │   │   │  │
│  │  │  └────────────────────────────────────────┘   │   │  │
│  │  └───────────────────────────────────────────────┘   │  │
│  │                                                      │  │
│  │  Private Service Connect:                            │  │
│  │  ├── Cloud Storage (via googleapis.com)              │  │
│  │  ├── Secret Manager (via googleapis.com)             │  │
│  │  └── Artifact Registry (via googleapis.com)          │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────┘
```

### Firewall Rules

```bash
# Allow IAP tunnel (Identity-Aware Proxy for SSH)
gcloud compute firewall-rules create allow-iap-ssh \
  --network vpc-ai-sandbox \
  --allow tcp:22 \
  --source-ranges 35.235.240.0/20 \
  --target-tags ai-sandbox \
  --description "Allow SSH via Identity-Aware Proxy"

# Allow internal VPC traffic
gcloud compute firewall-rules create allow-internal \
  --network vpc-ai-sandbox \
  --allow tcp,udp,icmp \
  --source-ranges 10.0.0.0/8 \
  --target-tags ai-sandbox

# Allow JupyterLab from corporate VPN (adjust source)
gcloud compute firewall-rules create allow-jupyterlab-vpn \
  --network vpc-ai-sandbox \
  --allow tcp:8888 \
  --source-ranges 192.168.0.0/16 \
  --target-tags ai-sandbox \
  --description "JupyterLab from VPN"

# Deny all other ingress (implicit, but make explicit for clarity)
gcloud compute firewall-rules create deny-all-ingress \
  --network vpc-ai-sandbox \
  --action deny \
  --direction ingress \
  --rules all \
  --priority 65534
```

### Private Google Access

Enable Private Google Access on the subnet to allow access to Google APIs (Cloud Storage, Secret Manager) without external IP:

```bash
gcloud compute networks subnets update subnet-sandbox-us-central1 \
  --region us-central1 \
  --enable-private-ip-google-access
```

### Cloud NAT (Controlled Internet Egress)

For controlled internet access (e.g., downloading model weights):

```bash
# Create Cloud Router
gcloud compute routers create router-sandbox \
  --network vpc-ai-sandbox \
  --region us-central1

# Create Cloud NAT
gcloud compute routers nats create nat-sandbox \
  --router router-sandbox \
  --region us-central1 \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips
```

For fully air-gapped environments, **skip Cloud NAT** and pre-stage all dependencies in Artifact Registry and Cloud Storage.

---

## IAM and Service Accounts

### Service Account Design

Each sandbox instance uses a **dedicated service account** with minimal permissions:

```bash
# Create dedicated service account
gcloud iam service-accounts create sa-ai-sandbox \
  --display-name "AI Sandbox Service Account" \
  --project prj-ai-sandbox

SA_EMAIL="sa-ai-sandbox@prj-ai-sandbox.iam.gserviceaccount.com"

# Grant Cloud Storage access (read/write to sandbox bucket only)
gcloud storage buckets add-iam-policy-binding gs://sandbox-models-prj \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectUser"

# Grant Secret Manager read access
gcloud projects add-iam-policy-binding prj-ai-sandbox \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --condition="expression=resource.name.startsWith('projects/prj-ai-sandbox/secrets/sandbox-'),title=sandbox-secrets-only"

# Grant Artifact Registry read access
gcloud projects add-iam-policy-binding prj-ai-sandbox \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.reader"

# Grant Cloud Logging write access
gcloud projects add-iam-policy-binding prj-ai-sandbox \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/logging.logWriter"

# Grant Cloud Monitoring write access
gcloud projects add-iam-policy-binding prj-ai-sandbox \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/monitoring.metricWriter"
```

### Human Developer Access via IAP

```bash
# Grant IAP SSH access to developers
gcloud projects add-iam-policy-binding prj-ai-sandbox \
  --member="group:sandbox-developers@company.com" \
  --role="roles/iap.tunnelResourceAccessor"

# SSH via IAP (no SSH keys needed, uses Google identity)
gcloud compute ssh vm-ai-sandbox \
  --project prj-ai-sandbox \
  --zone us-central1-a \
  --tunnel-through-iap

# Port-forward JupyterLab
gcloud compute ssh vm-ai-sandbox \
  --project prj-ai-sandbox \
  --zone us-central1-a \
  --tunnel-through-iap \
  -- -L 8888:localhost:8888
```

### RBAC Roles for Human Users

| Custom Role | Permissions | Assign To |
|-------------|------------|-----------|
| `Sandbox Developer` | compute.instances.start/stop, iap.tunnelResourceAccessor, storage.objectViewer | Developers |
| `Sandbox Admin` | compute.*, storage.*, logging.*, monitoring.* (project scope) | Team leads |
| `Sandbox Viewer` | logging.logEntries.list, monitoring.timeSeries.list | Auditors |

---

## Cloud Storage Considerations

### Bucket Design

```
gs://sandbox-models-{project_id}/
  ├── huggingface/              # Cached Hugging Face model weights
  ├── ollama/                   # Ollama model blobs (gguf files)
  └── custom/                   # Fine-tuned / custom models

gs://sandbox-datasets-{project_id}/
  ├── raw/                      # Original datasets
  ├── processed/                # Cleaned data
  └── outputs/                  # Model outputs

gs://sandbox-notebooks-{project_id}/
  └── {username}/               # Per-user notebooks
```

### Bucket Security

```bash
# Enable uniform bucket-level access (disable ACLs)
gcloud storage buckets update gs://sandbox-models-${PROJECT_ID} \
  --uniform-bucket-level-access

# Enable CMEK encryption
gcloud storage buckets update gs://sandbox-models-${PROJECT_ID} \
  --default-kms-key projects/${PROJECT_ID}/locations/us-central1/keyRings/sandbox-keyring/cryptoKeys/sandbox-key

# Set retention policy (prevent deletion for 30 days)
gcloud storage buckets update gs://sandbox-models-${PROJECT_ID} \
  --retention-period 30d

# Enable audit logging for the bucket
gcloud logging sinks create sandbox-storage-audit \
  logging.googleapis.com/projects/${PROJECT_ID}/logs/cloudaudit.googleapis.com%2Fdata_access \
  --log-filter='resource.type="gcs_bucket" AND resource.labels.bucket_name="sandbox-models-${PROJECT_ID}"'
```

### Lifecycle Policies

```json
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "SetStorageClass", "storageClass": "COLDLINE"},
      "condition": {"age": 90, "matchesStorageClass": ["NEARLINE"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365, "matchesStorageClass": ["COLDLINE"]}
    }
  ]
}
```

---

## Preemptible VM Guidance

### What Are Preemptible VMs?

Preemptible VMs are spare Compute Engine capacity offered at up to **70–80% discount**. They can be stopped by Google with **30 seconds notice** when capacity is needed elsewhere. Maximum runtime is 24 hours.

**Spot VMs** (the successor to preemptible) have no maximum runtime and are also available at similar discounts.

### When to Use Preemptible / Spot VMs

| Workload | Use Preemptible? | Notes |
|---------|-----------------|-------|
| Interactive Jupyter sessions | No | Interruption is too disruptive |
| Batch inference (stateless) | Yes | Retry on preemption |
| Model fine-tuning with checkpointing | Yes | Save every 10-20 min |
| Overnight evaluation runs | Yes | High availability windows overnight |
| CI/CD pipeline model testing | Yes | Retry logic handles interruption |

### Creating a Spot VM

```bash
gcloud compute instances create vm-ai-sandbox-spot \
  --machine-type n1-standard-8 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --provisioning-model SPOT \
  --instance-termination-action STOP \
  --image-family common-cu118 \
  --image-project deeplearning-platform-release \
  --boot-disk-size 100GB \
  --boot-disk-type pd-ssd \
  --subnet subnet-sandbox-us-central1 \
  --no-address \
  --service-account sa-ai-sandbox@prj-ai-sandbox.iam.gserviceaccount.com \
  --scopes cloud-platform \
  --tags ai-sandbox \
  --zone us-central1-a \
  --metadata startup-script='#!/bin/bash
    nvidia-smi
    # Mount Cloud Storage bucket
    gcsfuse sandbox-models-prj-ai-sandbox /mnt/models
  '
```

### Handling Preemption

```python
# preemption_handler.py — monitor GCE metadata for preemption signal
import requests
import time
import signal
import sys

METADATA_URL = "http://metadata.google.internal/computeMetadata/v1/instance/preempted"
HEADERS = {"Metadata-Flavor": "Google"}

def check_preemption():
    try:
        response = requests.get(METADATA_URL, headers=HEADERS, timeout=2)
        return response.text.strip() == "TRUE"
    except Exception:
        return False

def handle_preemption():
    print("Preemption detected! Saving checkpoint...")
    # Signal training script to save checkpoint
    # e.g., send SIGUSR1 to trainer process

if __name__ == "__main__":
    while True:
        if check_preemption():
            handle_preemption()
            sys.exit(0)
        time.sleep(5)
```

---

## Recommended Configuration Summary

| Parameter | Recommended Value |
|-----------|------------------|
| Machine Type | `n1-standard-4` + 1× T4 GPU (start); scale to `g2-standard-8` for L4 |
| Image | Deep Learning VM Image (CUDA 11.8, Ubuntu 22.04) |
| Boot Disk | pd-ssd, 100 GB |
| Data Disk | pd-ssd, 500 GB (models + datasets) |
| External IP | None |
| Network | Custom VPC + Firewall rules + Private Google Access |
| Access | IAP SSH tunnel (no SSH port open to internet) |
| Service Account | Dedicated, least-privilege |
| Provisioning | Spot VM for batch jobs; On-demand for interactive |
| Storage | Cloud Storage with uniform bucket-level access + CMEK |
| Monitoring | Cloud Monitoring + Cloud Logging + Cloud Audit Logs |
| Auto-shutdown | Cloud Scheduler + Cloud Functions on idle GPU metrics |
