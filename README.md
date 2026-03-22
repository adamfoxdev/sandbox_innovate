# 🛡️ Secure AI Sandbox Environments

[![Build Status](https://img.shields.io/github/actions/workflow/status/sandbox_innovate/sandbox_innovate/ci.yml?branch=main&label=build&style=flat-square)](https://github.com/sandbox_innovate/sandbox_innovate/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Security Policy](https://img.shields.io/badge/Security-Policy-red?style=flat-square)](docs/security/overview.md)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?style=flat-square&logo=terraform)](templates/)
[![Docker](https://img.shields.io/badge/Container-Docker-2496ED?style=flat-square&logo=docker)](templates/local-docker/)

> **A secure, modular developer sandbox platform for rapid experimentation with emerging AI tools.** Provides isolated, policy-driven environments that let teams prototype, validate, and iterate quickly while maintaining strong security, compliance, and reproducibility across Azure, AWS, GCP, and local infrastructure.

---

## 📋 Table of Contents

- [Why Secure AI Sandboxes?](#-why-secure-ai-sandboxes)
- [Quick Start](#-quick-start)
- [Architecture](#-architecture)
- [Documentation](#-documentation)
  - [Architecture Guides](#architecture-guides)
  - [Security & Compliance](#security--compliance)
  - [Cost Optimization](#cost-optimization)
  - [Setup Guides](#setup-guides)
  - [Developer Experience](#developer-experience)
  - [Enterprise Playbook](#enterprise-playbook)
- [Templates](#-templates)
- [Security](#-security)
- [Cost](#-cost)
- [Developer Experience](#-developer-experience)
- [Enterprise Readiness](#-enterprise-readiness)
- [Contributing](#-contributing)
- [License](#-license)

---

## 🎯 Why Secure AI Sandboxes?

Organizations adopting AI face a critical challenge: **innovation velocity vs. security posture**. Developers need freedom to experiment with large language models, fine-tuning pipelines, and agentic workflows — but uncontrolled experimentation introduces real risks:

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Data exfiltration via model prompts | Regulatory violation, IP loss | Network isolation, DLP controls |
| Unvetted model weights | Supply chain attack | Artifact scanning, signed images |
| Unconstrained cloud spend | Budget overrun | Quotas, auto-shutdown, spot instances |
| Shadow AI / ungoverned tools | Compliance failure | Policy-as-code, approved tool catalogs |
| Reproducibility gaps | Research waste | Versioned environments, MLflow, DVC |

**Secure AI Sandbox Environments** provides battle-tested templates and runbooks to eliminate these risks while accelerating your AI adoption journey.

### Benefits at a Glance

- 🔒 **Zero-trust network isolation** — sandboxes cannot reach production systems
- 💰 **Cost guardrails** — auto-shutdown, spot/preemptible instances, budget alerts
- 🚀 **Rapid provisioning** — from zero to GPU-backed JupyterLab in under 10 minutes
- 📋 **Compliance-ready** — SOC 2, ISO 27001, HIPAA-aligned configurations
- 🔄 **Reproducible** — every environment is versioned, immutable, and auditable

---

## ⚡ Quick Start

### Option 1: Local Docker (Fastest — 5 minutes)

```bash
# Clone the repository
git clone https://github.com/sandbox_innovate/sandbox_innovate.git
cd sandbox_innovate

# Start local AI sandbox (CPU mode)
cd templates/local-docker
docker compose up -d

# Access services
# Open WebUI: http://localhost:3000
# JupyterLab:  http://localhost:8888 (token: sandbox)
# Ollama API:  http://localhost:11434
```

### Option 2: Azure VM (Cloud — 10 minutes)

```bash
# Prerequisites: Azure CLI, Terraform >= 1.5
az login
cd templates/azure-vm
cp terraform.tfvars.example terraform.tfvars  # edit with your values
terraform init && terraform apply
```

### Option 3: AWS EC2 (Cloud — 10 minutes)

```bash
# Prerequisites: AWS CLI configured, Terraform >= 1.5
cd templates/aws-ec2
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

### Option 4: GCP Compute Engine (Cloud — 10 minutes)

```bash
# Prerequisites: gcloud CLI, Terraform >= 1.5
gcloud auth application-default login
cd templates/gcp-compute
cp terraform.tfvars.example terraform.tfvars
terraform init && terraform apply
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     SECURE AI SANDBOX PLATFORM                       │
├────────────────┬────────────────┬───────────────┬───────────────────┤
│   Azure VM     │   AWS EC2      │  GCP Compute  │  Local Docker     │
│  (NC/NV series)│  (g4dn/p3/g5) │  (A2/N1+GPU) │  (NVIDIA/CPU)    │
├────────────────┴────────────────┴───────────────┴───────────────────┤
│                        ISOLATION LAYER                                │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────────────────┐   │
│  │  VNet/VPC   │  │  NSG / SG /  │  │  Identity & Access       │   │
│  │  Subnets    │  │  Firewall     │  │  (AAD / IAM / SA)        │   │
│  └─────────────┘  └──────────────┘  └──────────────────────────┘   │
├─────────────────────────────────────────────────────────────────────┤
│                       WORKLOAD LAYER                                  │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐  ┌─────────────────┐   │
│  │ JupyterLab│  │  Ollama  │  │   vLLM   │  │  VS Code        │   │
│  │ (notebook)│  │ (local   │  │ (serving)│  │  Dev Container  │   │
│  └──────────┘  │  LLM)    │  └───────────┘  └─────────────────┘   │
│                └──────────┘                                          │
├─────────────────────────────────────────────────────────────────────┤
│                       GOVERNANCE LAYER                                │
│  ┌───────────┐  ┌──────────────┐  ┌──────────┐  ┌─────────────┐   │
│  │  Secrets  │  │  Audit Logs  │  │  Budget  │  │  Policy-as- │   │
│  │  (KMS /   │  │  (SIEM)      │  │  Alerts  │  │  Code       │   │
│  │   Vault)  │  └──────────────┘  └──────────┘  └─────────────┘   │
│  └───────────┘                                                       │
└─────────────────────────────────────────────────────────────────────┘
```

See [docs/architecture/overview.md](docs/architecture/overview.md) for the full deep-dive.

---

## 📚 Documentation

### Architecture Guides

| Guide | Description |
|-------|-------------|
| [Architecture Overview](docs/architecture/overview.md) | Decision matrix, network patterns, IAM overview |
| [Azure VM](docs/architecture/azure-vm.md) | NC/NV series, VNet, Entra ID, managed identity |
| [AWS EC2](docs/architecture/aws-ec2.md) | g4dn/p3/g5, VPC, IAM, spot instances |
| [GCP Compute Engine](docs/architecture/gcp-compute.md) | A2/N1+GPU, VPC, service accounts, preemptible |
| [Local Sandbox](docs/architecture/local-sandbox.md) | Docker, Podman, local GPU (CUDA/ROCm/MPS) |

### Security & Compliance

| Guide | Description |
|-------|-------------|
| [Security Overview](docs/security/overview.md) | Zero-trust, secrets, data classification, checklists |

### Cost Optimization

| Guide | Description |
|-------|-------------|
| [Cost Overview](docs/cost/overview.md) | Comparison tables, spot guidance, budget examples |

### Setup Guides

| Guide | Description |
|-------|-------------|
| [Azure VM Setup](docs/setup/azure-vm-setup.md) | CLI, Terraform, hardening, validation |
| [AWS EC2 Setup](docs/setup/aws-ec2-setup.md) | CLI, CloudFormation, Terraform, hardening |
| [GCP Setup](docs/setup/gcp-setup.md) | gcloud CLI, Terraform, hardening |
| [Local Docker Setup](docs/setup/local-docker-setup.md) | Docker Desktop, GPU passthrough, Ollama |

### Developer Experience

| Guide | Description |
|-------|-------------|
| [Developer Experience](docs/developer-experience.md) | Tooling, reproducibility, CI/CD integration |

### Enterprise Playbook

| Guide | Description |
|-------|-------------|
| [Enterprise Playbook](docs/enterprise-playbook.md) | ROI, onboarding, governance, training |
| [Resources](docs/resources.md) | Curated external links and tools |
| [Roadmap](docs/roadmap.md) | v1.x → v2.0 → long-term vision |

---

## 🗂️ Templates

| Template | Description |
|----------|-------------|
| [`templates/azure-vm/`](templates/azure-vm/) | Terraform: Azure VM with GPU, VNet, managed identity |
| [`templates/aws-ec2/`](templates/aws-ec2/) | Terraform: EC2 with GPU, VPC, IAM role |
| [`templates/gcp-compute/`](templates/gcp-compute/) | Terraform: GCE with T4 GPU, VPC, service account |
| [`templates/local-docker/`](templates/local-docker/) | Docker Compose: Ollama + Open WebUI + JupyterLab |
| [`templates/jupyterlab/`](templates/jupyterlab/) | Secure JupyterLab with GPU, auth, resource limits |
| [`templates/vscode-devcontainer/`](templates/vscode-devcontainer/) | VS Code Dev Container with CUDA + AI tools |

---

## 🔒 Security

This platform is built on **zero-trust** principles:

- **No sandbox can reach production** — enforced at the network layer (VNet/VPC peering rules, firewall policies)
- **All secrets in managed vaults** — Azure Key Vault, AWS Secrets Manager, GCP Secret Manager; never in environment variables or code
- **Least-privilege identities** — managed identities and service accounts with minimal IAM permissions
- **Audit logging enabled by default** — all API calls and data access logged to SIEM-compatible sinks
- **Model artifact scanning** — container images and model weights scanned before use

See [docs/security/overview.md](docs/security/overview.md) for the complete security guide.

---

## 💰 Cost

Typical monthly costs by team size:

| Team Size | Cloud Option | Est. Monthly Cost |
|-----------|-------------|-------------------|
| 1–5 devs | Local Docker (CPU) | $0 (hardware only) |
| 1–5 devs | AWS g4dn.xlarge spot | ~$50–$150 |
| 6–20 devs | Azure NC4as_T4_v3 × 4 | ~$400–$800 |
| 20+ devs | GCP A2 standard + preemptible | ~$1,200–$3,000 |

See [docs/cost/overview.md](docs/cost/overview.md) for detailed breakdowns and optimization strategies.

---

## 🧑‍💻 Developer Experience

- **One-command environment spin-up** via Docker Compose or Terraform
- **Pre-configured AI tool stack**: Ollama, vLLM, Hugging Face Transformers, LangChain, LlamaIndex
- **GPU-accelerated** JupyterLab and VS Code Dev Containers
- **Experiment tracking** with MLflow and DVC baked in
- **CI/CD integration** patterns for automated sandbox provisioning

See [docs/developer-experience.md](docs/developer-experience.md) for the full guide.

---

## 🏢 Enterprise Readiness

| Capability | Status |
|-----------|--------|
| Multi-cloud support (Azure / AWS / GCP) | ✅ |
| Infrastructure-as-Code (Terraform) | ✅ |
| Zero-trust network isolation | ✅ |
| Secrets management integration | ✅ |
| Audit logging | ✅ |
| Cost guardrails & auto-shutdown | ✅ |
| GPU support | ✅ |
| SOC 2 / ISO 27001 aligned configs | ✅ |
| Multi-tenant support | 🔜 v1.x |
| Policy-as-code (OPA/Sentinel) | 🔜 v2.0 |
| Enterprise dashboard | 🔜 Long-term |

See [docs/enterprise-playbook.md](docs/enterprise-playbook.md) and [docs/roadmap.md](docs/roadmap.md).

---

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines before submitting a pull request.

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m 'feat: add your feature'`
4. Push the branch: `git push origin feature/your-feature`
5. Open a Pull Request

Please ensure:
- All Terraform templates pass `terraform validate`
- Docker Compose files pass `docker compose config`
- Documentation is updated alongside code changes
- Security-sensitive changes include a threat model note

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

*Built with ❤️ for teams who want to move fast without breaking things.*
