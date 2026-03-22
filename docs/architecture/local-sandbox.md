# Local Developer Sandbox Guide

This guide covers setting up an AI experimentation sandbox on your local development machine — Windows, macOS, or Linux — using Docker, Podman, or native installation.

---

## Table of Contents

- [Overview & When to Use Local Sandboxes](#overview--when-to-use-local-sandboxes)
- [Windows Setup](#windows-setup)
- [macOS Setup](#macos-setup)
- [Linux Setup](#linux-setup)
- [Docker Containerized Environments](#docker-containerized-environments)
- [Podman Alternative](#podman-alternative)
- [Local GPU Usage](#local-gpu-usage)
  - [NVIDIA CUDA](#nvidia-cuda)
  - [AMD ROCm](#amd-rocm)
  - [Apple Silicon MPS](#apple-silicon-mps)
- [Security Hardening for Local Experimentation](#security-hardening-for-local-experimentation)
- [Preventing Corporate Data Leakage](#preventing-corporate-data-leakage)

---

## Overview & When to Use Local Sandboxes

Local sandboxes are ideal when:

- **Cost matters**: No cloud bill during exploration
- **Latency is critical**: No network roundtrip for inference
- **Internet is restricted**: Air-gapped or restricted corporate network
- **Small models**: 7B–13B parameter models fit in 8–24 GB VRAM
- **Quick iteration**: Rapid prompt engineering, small experiments

**Limitations**:
- Hardware-bound: can't scale beyond your GPU
- Not shared: colleagues can't access your environment
- No audit trail: local experiments aren't centrally logged
- No auto-shutdown: you're responsible for resource management

**Recommendation**: Start local for exploration; graduate to cloud when you need GPU scale, collaboration, or compliance.

---

## Windows Setup

### Prerequisites

1. **Windows 11 or Windows 10 (Build 19041+)** with WSL2 enabled:

   ```powershell
   # Enable WSL2 (run as Administrator)
   wsl --install
   # Restart, then install Ubuntu
   wsl --install -d Ubuntu-22.04
   ```

2. **Docker Desktop for Windows**: Download from [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/)
   - Enable WSL2 backend in Docker Desktop settings
   - Allocate sufficient memory: Settings → Resources → WSL Integration

3. **NVIDIA GPU (optional)**: Install [NVIDIA drivers for WSL2](https://docs.nvidia.com/cuda/wsl-user-guide/)

4. **Python environment** (in WSL2 Ubuntu):

   ```bash
   # In WSL2 terminal
   sudo apt update && sudo apt install -y python3.11 python3.11-venv python3-pip git curl
   ```

### Verify Installation

```powershell
# In PowerShell
docker version
docker run --rm hello-world

# In WSL2 terminal
nvidia-smi  # If you have NVIDIA GPU
python3.11 --version
```

---

## macOS Setup

### Prerequisites

#### Apple Silicon (M1/M2/M3/M4)

1. **Docker Desktop for Mac (Apple Silicon)**:

   ```bash
   # Using Homebrew
   brew install --cask docker
   # Or download from docker.com
   ```

2. **Python with pyenv**:

   ```bash
   brew install pyenv
   pyenv install 3.11.9
   pyenv global 3.11.9
   ```

3. **Ollama (native Apple Silicon binary)**:

   ```bash
   brew install ollama
   # Or download from ollama.ai
   ollama serve &
   ollama pull llama3.1:8b
   ```

   Ollama on Apple Silicon uses the **Metal Performance Shaders (MPS)** backend, delivering excellent performance on M-series chips.

#### Intel Mac

1. **Docker Desktop for Mac (Intel)**:

   ```bash
   brew install --cask docker
   ```

2. **Python**:

   ```bash
   brew install pyenv
   pyenv install 3.11.9
   pyenv global 3.11.9
   ```

   > Note: Intel Macs lack dedicated AI accelerators. CPU inference with GGUF quantized models is your best option.

### Verify Installation

```bash
# macOS
docker version
docker run --rm hello-world
python3 --version
ollama list  # If ollama installed
```

---

## Linux Setup

### Ubuntu 22.04 / Debian

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker Engine
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose plugin
sudo apt install -y docker-compose-plugin

# Install Python 3.11
sudo apt install -y python3.11 python3.11-venv python3-pip

# Install git and other tools
sudo apt install -y git curl wget unzip

# Install NVIDIA drivers (if applicable — adjust driver version)
sudo apt install -y nvidia-driver-535
sudo reboot
```

### RHEL / CentOS / Fedora

```bash
# Fedora
sudo dnf install -y docker docker-compose python3.11 git nvidia-driver

# Enable and start Docker
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```

### Verify Docker + GPU

```bash
docker version
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

---

## Docker Containerized Environments

Docker is the recommended approach for local sandboxes because it provides:

- **Reproducibility**: Same environment on every machine
- **Isolation**: Python package conflicts don't affect your host
- **Portability**: Move experiments to cloud with same container image
- **Easy cleanup**: `docker compose down -v` removes everything

### Using the Provided Template

```bash
# Clone the repository
git clone https://github.com/sandbox_innovate/sandbox_innovate.git
cd sandbox_innovate/templates/local-docker

# For GPU support (NVIDIA):
docker compose --profile gpu up -d

# For CPU only:
docker compose up -d

# View running services
docker compose ps

# View logs
docker compose logs -f ollama
```

Services available after startup:

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Open WebUI (Ollama UI) | http://localhost:3000 | Create account on first login |
| JupyterLab | http://localhost:8888 | Token: `sandbox` |
| Ollama API | http://localhost:11434 | None (API only) |

### Pulling Models

```bash
# Pull models via Ollama
docker exec -it ollama ollama pull llama3.1:8b
docker exec -it ollama ollama pull mistral:7b
docker exec -it ollama ollama pull phi3:mini

# Or use the Open WebUI to pull models via browser
```

### Custom JupyterLab Configuration

```bash
# Mount additional volumes for local datasets
docker compose -f docker-compose.yml -f docker-compose.override.yml up -d

# docker-compose.override.yml:
# services:
#   jupyterlab:
#     volumes:
#       - /path/to/your/data:/workspace/data:ro
```

---

## Podman Alternative

Podman is a daemonless, rootless container engine that many enterprises prefer for security reasons.

### Install Podman

```bash
# Ubuntu 22.04
sudo apt install -y podman podman-compose

# Fedora
sudo dnf install -y podman podman-compose

# macOS
brew install podman
podman machine init
podman machine start
```

### Using Podman Instead of Docker

```bash
# Podman is drop-in compatible with Docker commands
alias docker=podman

# Use podman-compose instead of docker compose
podman-compose up -d
```

### Rootless Mode (Security Advantage)

```bash
# Run containers as your user (no root required)
podman run --rm -it --name ollama \
  -v ollama_models:/root/.ollama \
  -p 11434:11434 \
  ollama/ollama
```

---

## Local GPU Usage

### NVIDIA CUDA

#### Installation

```bash
# Ubuntu 22.04 — Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

#### Verify GPU Access in Container

```bash
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

#### Common Models and VRAM Requirements

| Model | VRAM (Q4_K_M) | VRAM (FP16) | Fits in T4 (16GB)? |
|-------|--------------|-------------|-------------------|
| Phi-3 Mini 3.8B | ~2.5 GB | ~8 GB | ✅ |
| Llama 3.2 3B | ~2.0 GB | ~6 GB | ✅ |
| Mistral 7B | ~4.0 GB | ~14 GB | ✅ (Q4) / Barely (FP16) |
| Llama 3.1 8B | ~4.5 GB | ~16 GB | ✅ (Q4) |
| Llama 3.1 13B | ~7.5 GB | ~26 GB | ✅ (Q4) |
| Llama 3.1 70B | ~40 GB | ~140 GB | ❌ (needs 3–4× T4) |

### AMD ROCm

#### Installation

```bash
# Ubuntu 22.04 — AMD ROCm for Docker
# Install ROCm kernel driver
sudo apt install -y linux-headers-$(uname -r)
wget https://repo.radeon.com/amdgpu-install/6.0.2/ubuntu/jammy/amdgpu-install_6.0.60002-1_all.deb
sudo dpkg -i amdgpu-install_6.0.60002-1_all.deb
sudo amdgpu-install --usecase=rocm,dkms
sudo usermod -a -G render,video $USER
sudo reboot
```

#### Run Ollama with ROCm

```bash
docker run -d --name ollama-rocm \
  --device /dev/kfd \
  --device /dev/dri \
  -v ollama_models:/root/.ollama \
  -p 11434:11434 \
  ollama/ollama:rocm
```

#### Supported AMD GPUs

| GPU | VRAM | Status |
|-----|------|--------|
| RX 7900 XTX | 24 GB | ✅ Full support |
| RX 7900 XT | 20 GB | ✅ Full support |
| RX 6800 XT | 16 GB | ✅ Full support |
| RX 6700 XT | 12 GB | ✅ Full support |

### Apple Silicon MPS

#### Native Ollama (Best Performance on M-Series)

```bash
# Install Ollama natively (not in Docker — better MPS integration)
curl -fsSL https://ollama.ai/install.sh | sh
ollama serve &

# Pull and run a model
ollama pull llama3.1:8b
ollama run llama3.1:8b
```

#### PyTorch MPS Support

```python
import torch

device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
print(f"Using device: {device}")  # mps on Apple Silicon

# Example: run a Hugging Face model on MPS
from transformers import pipeline
pipe = pipeline("text-generation", model="microsoft/phi-2", device=device)
result = pipe("The future of AI is")
print(result)
```

#### Apple Silicon Model Capacity

| Chip | Unified Memory | Usable for Models |
|------|---------------|-------------------|
| M1 | 8–16 GB | Up to 7B models (Q4) |
| M1 Pro/Max | 16–64 GB | Up to 30B models (Q4) |
| M2 | 8–24 GB | Up to 13B models (Q4) |
| M2 Pro/Max | 16–96 GB | Up to 65B models (Q4) |
| M3 Max | 36–128 GB | Up to 70B models (Q4) |
| M4 Max | 48–128 GB | 70B+ models (Q4) |

---

## Security Hardening for Local Experimentation

### Container Security

```yaml
# In your docker-compose.yml, add security options:
services:
  jupyterlab:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    user: "1000:1000"  # Non-root user
```

### Network Isolation

Prevent sandbox containers from reaching corporate services:

```yaml
# docker-compose.yml
networks:
  sandbox_internal:
    driver: bridge
    internal: true        # No internet access
    ipam:
      config:
        - subnet: 172.20.0.0/24

  # Separate network for Ollama (needs internet for model downloads)
  ollama_external:
    driver: bridge
```

### Secrets in Local Development

- **Never** store API keys in notebooks or code files
- Use `.env` files (never commit to git — add to `.gitignore`)
- Prefer a local password manager (1Password CLI, Bitwarden CLI) to inject secrets
- For team environments, use HashiCorp Vault dev server locally

```bash
# .env file (never commit this)
OPENAI_API_KEY=sk-...
HUGGINGFACE_TOKEN=hf_...
ANTHROPIC_API_KEY=...

# Load in docker-compose
services:
  jupyterlab:
    env_file:
      - .env
```

---

## Preventing Corporate Data Leakage

### Key Risks in Local AI Experimentation

1. **Uploading sensitive data to external model APIs** (OpenAI, Anthropic, etc.)
2. **Model prompts containing PII or proprietary information logged by providers**
3. **Committing datasets or secrets to git repositories**

### Mitigations

1. **Run models locally** (Ollama, llama.cpp) — data never leaves your machine:

   ```bash
   # Use Ollama instead of OpenAI API for sensitive data
   ollama run llama3.1:8b "Summarize this: [sensitive data]"
   ```

2. **Git pre-commit hooks** to prevent accidental data commits:

   ```bash
   pip install detect-secrets pre-commit
   # Configure .pre-commit-config.yaml with detect-secrets
   pre-commit install
   ```

3. **`.gitignore` template** for AI projects:

   ```
   # Datasets (potentially sensitive)
   data/
   datasets/
   *.csv
   *.jsonl
   *.parquet

   # Model weights (large and proprietary)
   *.bin
   *.safetensors
   *.gguf
   *.ggml

   # Secrets
   .env
   *.pem
   *.key
   secrets/

   # Jupyter checkpoints
   .ipynb_checkpoints/
   ```

4. **Data classification**: Before experimenting, classify your data:
   - 🟢 **Public**: Safe to send to any API, safe to commit
   - 🟡 **Internal**: Use local models only; do not commit
   - 🔴 **Confidential/PII**: Never use in AI experiments without anonymization
   - ⛔ **Restricted**: Requires security review before any AI usage
