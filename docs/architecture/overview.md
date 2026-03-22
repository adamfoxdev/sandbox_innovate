# Architecture Overview: Secure AI Sandbox Environments

This document provides a comprehensive deep-dive into the architecture of the Secure AI Sandbox platform, covering all supported deployment targets, decision frameworks, network isolation patterns, and identity & access control.

---

## Table of Contents

- [Deployment Topology](#deployment-topology)
- [Sandbox Types](#sandbox-types)
  - [Cloud-Based Sandboxes](#cloud-based-sandboxes)
  - [Local Developer Sandboxes](#local-developer-sandboxes)
- [Decision Matrix](#decision-matrix)
- [Network Isolation Patterns](#network-isolation-patterns)
- [Identity & Access Control Overview](#identity--access-control-overview)
- [Data Flow & Security Boundaries](#data-flow--security-boundaries)
- [Observability Architecture](#observability-architecture)

---

## Deployment Topology

```
                        ┌──────────────────────────────────────────┐
                        │          CORPORATE NETWORK               │
                        │                                          │
                        │  ┌────────────┐    ┌─────────────────┐  │
                        │  │  Identity  │    │   Policy Store  │  │
                        │  │  Provider  │    │  (OPA / Azure   │  │
                        │  │  (Entra /  │    │   Policy /      │  │
                        │  │   Okta)    │    │   AWS Config)   │  │
                        │  └─────┬──────┘    └────────┬────────┘  │
                        │        │                    │            │
                        └────────┼────────────────────┼────────────┘
                                 │  AuthN/AuthZ        │ Policy eval
          ┌──────────────────────┼────────────────────┼────────────────┐
          │                 SANDBOX LAYER              │                │
          │                                           │                │
          │  ┌──────────────┐  ┌──────────────┐  ┌──┴────────────┐   │
          │  │  Azure VM    │  │   AWS EC2    │  │  GCP Compute  │   │
          │  │  Sandbox     │  │   Sandbox    │  │  Sandbox      │   │
          │  │  (VNet)      │  │   (VPC)      │  │  (VPC)        │   │
          │  └──────────────┘  └──────────────┘  └───────────────┘   │
          │                                                            │
          │  ┌─────────────────────────────────────────────────────┐  │
          │  │              Local Developer Sandbox                 │  │
          │  │     (Docker / Podman — no cloud dependency)          │  │
          │  └─────────────────────────────────────────────────────┘  │
          │                                                            │
          │  Common Services (injected per sandbox):                   │
          │  • Secrets: Key Vault / Secrets Manager / Secret Manager   │
          │  • Logging: Log Analytics / CloudWatch / Cloud Logging      │
          │  • Artifacts: ACR / ECR / Artifact Registry                │
          └────────────────────────────────────────────────────────────┘
```

---

## Sandbox Types

### Cloud-Based Sandboxes

Cloud sandboxes are the recommended deployment model for teams that need:

- GPU compute beyond what local hardware can provide
- Persistent shared storage accessible to multiple developers
- Compliance-auditable infrastructure with centralized logging
- Reproducibility across team members regardless of their local OS

#### Azure VM Sandbox

- **Compute**: NC4as_T4_v3 (T4 GPU), NC6s_v3 (V100), NV6ads_A10_v5 (A10 GPU)
- **Isolation**: Azure Virtual Network, Network Security Groups, Private Endpoints
- **Identity**: Microsoft Entra ID, Managed Identity (system or user-assigned)
- **Secrets**: Azure Key Vault with RBAC
- **Storage**: Azure Blob Storage, Azure Files (SMB/NFS)
- **Shutdown**: Azure DevTest Labs auto-shutdown or Azure Automation runbooks

See [azure-vm.md](azure-vm.md) for the full guide.

#### AWS EC2 Sandbox

- **Compute**: g4dn.xlarge (T4 GPU), p3.2xlarge (V100), g5.xlarge (A10G GPU)
- **Isolation**: VPC, private subnet, Security Groups, VPC Endpoints
- **Identity**: IAM roles, Instance Profiles, AWS SSO
- **Secrets**: AWS Secrets Manager, Parameter Store
- **Storage**: S3 buckets (private, versioned), EBS volumes
- **Cost**: Spot Instances for up to 90% savings on interruptible workloads

See [aws-ec2.md](aws-ec2.md) for the full guide.

#### GCP Compute Engine Sandbox

- **Compute**: n1-standard-4 + NVIDIA T4 GPU, a2-highgpu-1g (A100 GPU)
- **Isolation**: VPC networks, subnets, firewall rules, Private Google Access
- **Identity**: Service Accounts, Workload Identity Federation
- **Secrets**: Secret Manager
- **Storage**: Cloud Storage buckets (uniform bucket-level access)
- **Cost**: Preemptible VMs for batch/experimental workloads

See [gcp-compute.md](gcp-compute.md) for the full guide.

---

### Local Developer Sandboxes

Local sandboxes eliminate cloud costs during early exploration and are ideal when:

- Models fit in local GPU VRAM (e.g., 7B–13B parameter models on a 24GB GPU)
- The developer has a workstation with dedicated GPU (NVIDIA / AMD / Apple Silicon)
- Corporate network policies restrict cloud egress for model downloads
- Completely air-gapped experimentation is required

#### Docker / Podman

- Containerized, repeatable environments
- NVIDIA Container Toolkit enables GPU passthrough into containers
- AMD ROCm images available for Radeon GPUs
- Apple Silicon supported via CPU or Metal (MPS) backends

#### Native / Bare-metal

- Fastest inference for large models (no container overhead on GPU)
- Harder to reproduce across team members
- Best combined with `pyenv`, `conda`, or `uv` for environment management

See [local-sandbox.md](local-sandbox.md) for the full guide.

---

## Decision Matrix

Use this matrix to select the right sandbox type for your use case:

| Criteria | Local Docker | Azure VM | AWS EC2 | GCP Compute |
|----------|-------------|----------|---------|-------------|
| **Cost (low usage)** | 🟢 Free | 🟡 Pay-per-use | 🟡 Pay-per-use | 🟡 Pay-per-use |
| **Cost (heavy usage)** | 🟡 Hardware amortized | 🟡 Spot savings | 🟢 Spot up to 90% | 🟢 Preemptible |
| **GPU availability** | 🟡 Own hardware | 🟢 On-demand | 🟢 On-demand | 🟢 On-demand |
| **Setup time** | 🟢 5 min | 🟡 10–15 min | 🟡 10–15 min | 🟡 10–15 min |
| **Collaboration** | 🔴 Single-user | 🟢 Shared VM / NFS | 🟢 Shared / EFS | 🟢 Shared / GCS |
| **Compliance audit** | 🔴 Limited | 🟢 Full audit trail | 🟢 Full audit trail | 🟢 Full audit trail |
| **Internet access control** | 🟡 Manual | 🟢 NSG/UDR | 🟢 SG/NACL | 🟢 Firewall rules |
| **Secrets management** | 🟡 Manual | 🟢 Key Vault | 🟢 Secrets Manager | 🟢 Secret Manager |
| **Corporate SSO** | 🔴 N/A | 🟢 Entra ID | 🟢 AWS SSO | 🟢 Cloud Identity |
| **Auto-shutdown** | 🟡 Manual | 🟢 Built-in | 🟡 Scripted | 🟡 Scripted |
| **Existing Azure investment** | — | 🟢 Best fit | 🟡 Dual-cloud | 🟡 Dual-cloud |
| **Existing AWS investment** | — | 🟡 Dual-cloud | 🟢 Best fit | 🟡 Dual-cloud |
| **Existing GCP investment** | — | 🟡 Dual-cloud | 🟡 Dual-cloud | 🟢 Best fit |

### Recommended Decision Flow

```
Is this a single developer exploring locally?
  └─ YES → Local Docker (templates/local-docker)
  └─ NO  → Is it a team experiment (< 1 week)?
              └─ YES → Local Docker or cheapest cloud spot instance
              └─ NO  → Does your company use Azure?
                          └─ YES → Azure VM sandbox
                          └─ NO  → Does your company use AWS?
                                      └─ YES → AWS EC2 sandbox
                                      └─ NO  → GCP Compute Engine sandbox
```

---

## Network Isolation Patterns

### Pattern 1: Fully Isolated Sandbox (Recommended for Regulated Industries)

```
Internet ─── [BLOCKED] ─── Sandbox VNet/VPC
                             │
                             ├── Private endpoint → Model Registry (ACR/ECR/Artifact Registry)
                             ├── Private endpoint → Secrets (Key Vault/Secrets Manager)
                             └── Private endpoint → Storage (Blob/S3/GCS)
```

No internet egress. All dependencies (base images, model weights, Python packages) must be pre-staged in internal registries.

**Use case**: HIPAA, PCI-DSS, financial services, defense contractors.

### Pattern 2: Egress-Filtered Sandbox (Recommended Default)

```
Internet ─── [FILTERED via Proxy/Firewall] ─── Sandbox VNet/VPC
               Allow: *.huggingface.co, *.ollama.ai, pypi.org
               Block: *.corp-internal.*, S3 prod buckets, DB endpoints
```

Controlled internet access for model downloads. Corporate systems blocked.

**Use case**: Most enterprise teams. Balances convenience with security.

### Pattern 3: Developer-Convenience Sandbox (Not for Production Data)

```
Internet ─── [OPEN] ─── Sandbox VNet/VPC
               Block: Corporate network peering
               Block: Production resource access
```

Full internet access but isolated from production. Suitable for public model exploration with no sensitive data.

**Use case**: Innovation labs, hackathons, POC work with non-sensitive data.

---

## Identity & Access Control Overview

### Principle: One Identity Per Sandbox

Every sandbox environment gets a **dedicated, non-human identity**:

| Cloud | Identity Type | Permissions Scope |
|-------|--------------|-------------------|
| Azure | System-assigned Managed Identity | Resource group scope |
| AWS | EC2 Instance Profile (IAM Role) | Specific S3 buckets + Secrets Manager paths |
| GCP | Dedicated Service Account | Project-level with specific IAM bindings |
| Local | No cloud identity needed | Local secrets via `.env` (dev only) |

### Human Access: Just-In-Time (JIT)

Developers do **not** have standing access to sandbox VMs:

- **Azure**: JIT VM access via Microsoft Defender for Cloud (max 8-hour sessions)
- **AWS**: Systems Manager Session Manager (no SSH port open, session logged)
- **GCP**: Identity-Aware Proxy (IAP) tunneling

### RBAC Model

```
┌─────────────────────────────────────────────────────┐
│                  Role Hierarchy                      │
│                                                      │
│  sandbox-admin    → Create/delete sandboxes          │
│  sandbox-operator → Start/stop, access logs          │
│  sandbox-user     → Connect, run workloads           │
│  sandbox-viewer   → Read logs and outputs only       │
└─────────────────────────────────────────────────────┘
```

---

## Data Flow & Security Boundaries

```
Developer Laptop
      │
      │  SSH/SSM/IAP (authenticated, logged)
      ▼
┌─────────────────────────────────────┐
│           Sandbox VM                │
│                                     │
│  ┌──────────┐   ┌────────────────┐  │
│  │ JupyterLab│   │  Ollama/vLLM  │  │
│  │ (8888)   │   │  (11434)       │  │
│  └────┬─────┘   └───────┬────────┘  │
│       │                 │           │
│  ┌────▼─────────────────▼────────┐  │
│  │    Local network (sandbox)    │  │  ← No route to corporate systems
│  └───────────────────────────────┘  │
│                 │                   │
│          ┌──────▼──────┐            │
│          │ Private      │            │
│          │ Endpoints    │            │
│          └──────┬───────┘            │
└─────────────────┼───────────────────┘
                  │
          ┌───────▼──────────────────┐
          │  Approved Cloud Services  │
          │  • Model Registry         │
          │  • Secrets Store          │
          │  • Artifact Storage       │
          │  • Audit Log Sink         │
          └───────────────────────────┘
```

No data path exists from the sandbox to production databases, internal APIs, or other sandboxes. All egress is either blocked or routed through private endpoints to approved services only.

---

## Observability Architecture

Every sandbox emits three categories of telemetry:

### 1. Infrastructure Logs
- VM boot events, shutdown events, network flow logs
- Sent to: Log Analytics Workspace / CloudWatch / Cloud Logging

### 2. Access Audit Logs
- Authentication events, SSH sessions, API calls to cloud services
- Sent to: Microsoft Sentinel / AWS CloudTrail / Cloud Audit Logs

### 3. Workload Metrics
- GPU utilization, memory usage, disk I/O
- Sent to: Azure Monitor / CloudWatch Metrics / Cloud Monitoring
- Dashboards available in Grafana or cloud-native tools

### Alerting

| Alert | Threshold | Action |
|-------|-----------|--------|
| Sandbox idle (no GPU/CPU activity) | 30 minutes | Auto-shutdown |
| Unexpected outbound connection | Any to corporate IP range | Block + alert security team |
| Secret access outside sandbox | Any | Page on-call |
| Cost threshold exceeded | Configurable per team | Email + Slack alert |
