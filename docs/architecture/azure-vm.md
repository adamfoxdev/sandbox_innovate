# Azure VM Sandbox Guide

This guide covers everything you need to know about running AI sandbox environments on Azure Virtual Machines, including hardware selection, cost analysis, network security, and identity management.

---

## Table of Contents

- [Recommended VM Sizes for AI Workloads](#recommended-vm-sizes-for-ai-workloads)
- [GPU vs CPU Tradeoffs](#gpu-vs-cpu-tradeoffs)
- [Cost Estimates](#cost-estimates)
- [Network Isolation with VNet and NSG](#network-isolation-with-vnet-and-nsg)
- [Azure AD / Entra ID Access Control](#azure-ad--entra-id-access-control)
- [Storage and Data-Egress Considerations](#storage-and-data-egress-considerations)
- [Managed Identity Usage](#managed-identity-usage)
- [Auto-Shutdown Configuration](#auto-shutdown-configuration)
- [Recommended Configuration Summary](#recommended-configuration-summary)

---

## Recommended VM Sizes for AI Workloads

Azure offers several GPU-enabled VM series suitable for AI experimentation. The following table covers the most relevant options:

### NC Series (NVIDIA Tesla / T4 / V100)

| VM Size | GPU | GPU VRAM | vCPUs | RAM | Best For |
|---------|-----|----------|-------|-----|----------|
| `Standard_NC4as_T4_v3` | 1× NVIDIA T4 | 16 GB | 4 | 28 GB | 7B–13B model inference, fine-tuning small models |
| `Standard_NC8as_T4_v3` | 1× NVIDIA T4 | 16 GB | 8 | 56 GB | 13B–34B models, multi-user shared sandbox |
| `Standard_NC16as_T4_v3` | 1× NVIDIA T4 | 16 GB | 16 | 110 GB | Large batch inference, dataset processing |
| `Standard_NC64as_T4_v3` | 4× NVIDIA T4 | 64 GB | 64 | 440 GB | 70B+ models, multi-GPU experiments |
| `Standard_NC6s_v3` | 1× NVIDIA V100 | 16 GB | 6 | 112 GB | Fast fine-tuning, training experiments |
| `Standard_NC12s_v3` | 2× NVIDIA V100 | 32 GB | 12 | 224 GB | Distributed training, 30B+ models |

### NV Series (NVIDIA A10 — Visualization + Inference)

| VM Size | GPU | GPU VRAM | vCPUs | RAM | Best For |
|---------|-----|----------|-------|-----|----------|
| `Standard_NV6ads_A10_v5` | 1/6× NVIDIA A10 | 4 GB | 6 | 55 GB | Lightweight inference, UI-heavy workloads |
| `Standard_NV18ads_A10_v5` | 1/2× NVIDIA A10 | 12 GB | 18 | 220 GB | Mid-size model inference |
| `Standard_NV36ads_A10_v5` | 1× NVIDIA A10 | 24 GB | 36 | 440 GB | 13B–30B models at high throughput |

### ND Series (NVIDIA A100 — Large-Scale Training)

| VM Size | GPU | GPU VRAM | vCPUs | RAM | Best For |
|---------|-----|----------|-------|-----|----------|
| `Standard_ND96asr_v4` | 8× NVIDIA A100 | 320 GB | 96 | 900 GB | Large model training, 70B+ fine-tuning |
| `Standard_ND96amsr_A100_v4` | 8× NVIDIA A100 80GB | 640 GB | 96 | 1900 GB | Full-scale LLM fine-tuning |

### CPU-Only Options (No GPU)

| VM Size | vCPUs | RAM | Best For |
|---------|-------|-----|----------|
| `Standard_D4s_v5` | 4 | 16 GB | GGUF/llama.cpp CPU inference for small models |
| `Standard_D16s_v5` | 16 | 64 GB | Larger CPU inference, data preprocessing |
| `Standard_D32s_v5` | 32 | 128 GB | Batch data processing, embedding generation |

---

## GPU vs CPU Tradeoffs

### When to Choose GPU

- Running inference on models > 3B parameters at acceptable latency (< 5 sec/response)
- Fine-tuning or QLoRA training on any model
- Generating embeddings at scale (> 10,000 documents/hour)
- Running multimodal models (vision + language)
- Experimenting with vLLM or TGI for high-throughput serving

### When CPU Is Sufficient

- Prototyping with small models (< 3B parameters, GGUF Q4 quantized)
- Running LangChain/LlamaIndex pipelines against remote API endpoints (OpenAI, Azure OpenAI)
- Data preparation, cleaning, and pre-processing
- Testing prompt templates and agent logic without local inference
- Cost-sensitive exploration where latency > 10 sec/response is acceptable

### Performance Reference (T4 GPU)

| Model | Quantization | Tokens/sec (T4) | Tokens/sec (32-core CPU) |
|-------|-------------|-----------------|--------------------------|
| Llama 3.1 8B | Q4_K_M | ~45 | ~8 |
| Llama 3.1 70B | Q4_K_M | ~4 (requires 2× T4) | Not feasible |
| Mistral 7B | Q4_K_M | ~50 | ~10 |
| Phi-3 Mini 3.8B | Q4_K_M | ~80 | ~20 |

---

## Cost Estimates

All prices are **East US region, pay-as-you-go** (as of 2024). Actual prices vary by region and contract. Check [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/) for current rates.

### On-Demand Pricing

| VM Size | Hourly Cost | 8h/day (20 days/mo) | Full Month (730h) |
|---------|------------|---------------------|-------------------|
| `Standard_NC4as_T4_v3` | ~$0.526 | ~$84 | ~$384 |
| `Standard_NC8as_T4_v3` | ~$0.752 | ~$120 | ~$549 |
| `Standard_NC6s_v3` | ~$1.14 | ~$182 | ~$832 |
| `Standard_NV36ads_A10_v5` | ~$2.28 | ~$365 | ~$1,664 |
| `Standard_D4s_v5` (CPU only) | ~$0.192 | ~$31 | ~$140 |

### Reserved Instance Savings (1-year)

| VM Size | On-Demand/mo | 1-yr Reserved/mo | Savings |
|---------|-------------|-----------------|---------|
| `Standard_NC4as_T4_v3` | $384 | ~$230 | ~40% |
| `Standard_NC8as_T4_v3` | $549 | ~$330 | ~40% |
| `Standard_NC6s_v3` | $832 | ~$490 | ~41% |

### Spot Instance Savings

Azure Spot VMs offer 60–90% discounts but can be evicted with 30 seconds notice:

| VM Size | Spot Price/hr (approx) | Savings vs On-Demand |
|---------|----------------------|----------------------|
| `Standard_NC4as_T4_v3` | ~$0.08–$0.15 | 70–85% |
| `Standard_NC8as_T4_v3` | ~$0.15–$0.25 | 66–80% |

**Recommendation**: Use Spot for batch inference and training jobs. Use on-demand or reserved for interactive development sessions.

### Storage Costs (Additional)

| Storage Type | Cost | Recommended Use |
|-------------|------|----------------|
| Azure Blob (LRS, Hot) | ~$0.018/GB/mo | Model weights, datasets |
| Azure Files (Standard) | ~$0.060/GB/mo | Shared notebooks |
| Managed Disk (P30 128GB) | ~$19.17/mo | OS disk |

---

## Network Isolation with VNet and NSG

### Virtual Network Architecture

```
┌──────────────────────────────────────────────────┐
│  Resource Group: rg-ai-sandbox                    │
│                                                   │
│  ┌─────────────────────────────────────────────┐  │
│  │  VNet: vnet-ai-sandbox (10.0.0.0/16)        │  │
│  │                                             │  │
│  │  ┌───────────────────────────────────────┐  │  │
│  │  │  Subnet: snet-sandbox (10.0.1.0/24)   │  │  │
│  │  │                                       │  │  │
│  │  │  ┌─────────────┐  ┌───────────────┐  │  │  │
│  │  │  │  AI Sandbox  │  │  Bastion Host │  │  │  │
│  │  │  │  VM (private │  │  (optional)   │  │  │  │
│  │  │  │  IP only)    │  └───────────────┘  │  │  │
│  │  │  └─────────────┘                      │  │  │
│  │  └───────────────────────────────────────┘  │  │
│  │                                             │  │
│  │  Private Endpoints:                         │  │
│  │  ├── Key Vault (10.0.2.4)                   │  │
│  │  ├── Storage Account (10.0.2.5)             │  │
│  │  └── Container Registry (10.0.2.6)          │  │
│  └─────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

### Network Security Group Rules

The NSG attached to `snet-sandbox` enforces:

**Inbound Rules:**

| Priority | Name | Source | Destination | Port | Action |
|----------|------|--------|-------------|------|--------|
| 100 | AllowSSHFromBastion | Bastion subnet | Any | 22 | Allow |
| 200 | AllowJupyterFromCorp | Corporate IP range | Any | 8888 | Allow |
| 4096 | DenyAllInbound | Any | Any | Any | Deny |

**Outbound Rules:**

| Priority | Name | Source | Destination | Port | Action |
|----------|------|--------|-------------|------|--------|
| 100 | AllowPrivateEndpoints | Any | VNet | Any | Allow |
| 200 | AllowAzureServices | Any | AzureCloud service tag | 443 | Allow |
| 300 | AllowHuggingFace | Any | Internet | 443 | Allow (optional) |
| 4096 | DenyAllOutbound | Any | Any | Any | Deny |

> **Note**: Rule 300 (HuggingFace) should be removed in fully air-gapped environments. Pre-stage model weights in Azure Container Registry or Azure Blob Storage instead.

### User Defined Route (UDR)

For egress-filtered environments, route all internet traffic through Azure Firewall or a proxy VM:

```
0.0.0.0/0 → Azure Firewall / NVA (10.0.0.4)
10.0.0.0/8 → VNet local
```

---

## Azure AD / Entra ID Access Control

### Human User Access

1. **JIT VM Access** (Recommended): Enable Microsoft Defender for Cloud JIT access. Users request access via portal/CLI; access is granted for 1–8 hours.

   ```bash
   # Request JIT access via CLI
   az security jit-policy initiate \
     --resource-group rg-ai-sandbox \
     --name default \
     --virtual-machines '[{"id": "/subscriptions/.../virtualMachines/vm-ai-sandbox", "ports": [{"number": 22, "duration": "PT4H", "allowedSourceAddressPrefix": "MY_IP"}]}]'
   ```

2. **Azure Bastion** (No public IP): Access VMs through browser-based SSH/RDP with Entra ID authentication.

3. **Entra ID-authenticated SSH**: Enable Entra ID login extension on Linux VMs:

   ```bash
   az vm extension set \
     --publisher Microsoft.Azure.ActiveDirectory \
     --name AADSSHLoginForLinux \
     --resource-group rg-ai-sandbox \
     --vm-name vm-ai-sandbox
   ```

### RBAC Roles

Assign these built-in roles to sandbox users:

| Role | Access Level | Assign To |
|------|-------------|-----------|
| `Virtual Machine User Login` | SSH as regular user | Developers |
| `Virtual Machine Administrator Login` | SSH as admin | Team leads |
| `Reader` | View resources, read logs | All sandbox users |
| `Key Vault Secrets User` | Read secrets | Service accounts, developers (for dev only) |

---

## Storage and Data-Egress Considerations

### Tiered Storage Strategy

```
Model Weights (large, infrequently changed)
  → Azure Blob Storage, Cool tier, LRS
  → Example: 7B model ≈ 4 GB, stored in sa-sandbox-models container

Training Datasets
  → Azure Blob Storage, Hot tier, ZRS (if team-shared)
  → Apply lifecycle policy: move to Cool after 30 days

Experiment Outputs / Checkpoints
  → Azure Blob Storage, Hot tier
  → Lifecycle: delete after 90 days unless tagged 'keep'

Notebooks (team-shared)
  → Azure Files (SMB), mounted in VM via NFS
  → Daily backup via Azure Backup
```

### Data Exfiltration Prevention

1. **Storage firewall**: Restrict blob storage to VNet only:

   ```bash
   az storage account network-rule add \
     --account-name sasandboxmodels \
     --vnet-name vnet-ai-sandbox \
     --subnet snet-sandbox
   az storage account update \
     --name sasandboxmodels \
     --default-action Deny
   ```

2. **No public IP on VM**: Prevent direct data uploads to external services.

3. **Microsoft Defender for Storage**: Enable anomaly detection on storage accounts.

4. **Egress limits**: Azure Firewall FQDN rules control which external endpoints are reachable.

### Data Egress Costs

| Transfer Type | Cost |
|--------------|------|
| Ingress (data in) | Free |
| Egress to internet (first 100 GB/mo) | $0.087/GB |
| Egress to internet (100 GB – 10 TB/mo) | $0.083/GB |
| Within same region | Free |
| Between Azure regions | $0.02/GB |

**Optimization**: Keep model weights and datasets in the same Azure region as the sandbox VM to avoid inter-region egress charges.

---

## Managed Identity Usage

Every sandbox VM should use a **system-assigned managed identity** rather than service principal credentials stored in environment variables.

### Enabling Managed Identity

```bash
# Enable system-assigned managed identity on VM
az vm identity assign \
  --name vm-ai-sandbox \
  --resource-group rg-ai-sandbox
```

### Granting Permissions

```bash
# Get the managed identity principal ID
PRINCIPAL_ID=$(az vm identity show \
  --name vm-ai-sandbox \
  --resource-group rg-ai-sandbox \
  --query principalId -o tsv)

# Grant Key Vault Secrets User role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-ai-sandbox/providers/Microsoft.KeyVault/vaults/kv-ai-sandbox

# Grant Storage Blob Data Reader role
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Storage Blob Data Reader" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/rg-ai-sandbox/providers/Microsoft.Storage/storageAccounts/sasandboxmodels
```

### Using Managed Identity in Code

```python
from azure.identity import ManagedIdentityCredential
from azure.keyvault.secrets import SecretClient

# No credentials needed — identity from VM metadata service
credential = ManagedIdentityCredential()
client = SecretClient(vault_url="https://kv-ai-sandbox.vault.azure.net/", credential=credential)

secret = client.get_secret("huggingface-api-token")
print(secret.value)
```

---

## Auto-Shutdown Configuration

Configure automatic shutdown to prevent idle GPU spend:

```bash
# Set auto-shutdown at 8 PM UTC daily
az vm auto-shutdown \
  --resource-group rg-ai-sandbox \
  --name vm-ai-sandbox \
  --time 2000 \
  --email "team@company.com"
```

For more sophisticated scheduling (e.g., weekdays only), use Azure Automation or a Logic App triggered by Azure Monitor idle CPU metrics.

---

## Recommended Configuration Summary

| Parameter | Recommended Value |
|-----------|------------------|
| VM Size | `Standard_NC4as_T4_v3` (start here; scale up as needed) |
| OS Image | `Ubuntu 22.04 LTS` |
| OS Disk | Premium SSD 128 GB |
| Data Disk | Premium SSD 256 GB (models + datasets) |
| Public IP | None |
| Network | Private VNet + NSG + Private Endpoints |
| Identity | System-assigned Managed Identity |
| Auto-shutdown | 20:00 UTC daily |
| Spot | Yes, for batch jobs; No for interactive sessions |
| Backup | Azure Backup for data disk (weekly) |
| Monitoring | Azure Monitor + Log Analytics Workspace |
