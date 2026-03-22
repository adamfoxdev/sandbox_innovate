# Local Docker Sandbox Setup Guide

Step-by-step instructions for setting up an AI sandbox environment using Docker Compose on your local machine, including GPU passthrough, Ollama, vLLM, and JupyterLab.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Docker Compose Configuration](#docker-compose-configuration)
- [GPU Passthrough Configuration](#gpu-passthrough-configuration)
- [Security Configuration](#security-configuration)
- [Running AI Models (Ollama, vLLM)](#running-ai-models-ollama-vllm)
- [Validation Tests](#validation-tests)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Docker Desktop (Windows / macOS)

1. Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
2. Ensure WSL2 backend is enabled (Windows)
3. Allocate at least 8 GB RAM to Docker: Settings → Resources → Memory

### Docker Engine (Linux)

```bash
# Install Docker Engine
curl -fsSL https://get.docker.com | sudo bash
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker version
docker compose version
```

### NVIDIA Container Toolkit (GPU Support — Linux)

```bash
# Step 1: Install NVIDIA driver (if not already installed)
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers install
# Reboot: sudo reboot

# Step 2: Install NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

# Step 3: Configure Docker runtime
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# Step 4: Verify
docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi
```

### NVIDIA Container Toolkit (Windows with WSL2)

```powershell
# Install NVIDIA driver for WSL2 on Windows (NOT inside WSL2)
# Download from: https://www.nvidia.com/Download/index.aspx
# Select: Windows, then "CUDA on WSL" option

# In WSL2, verify:
nvidia-smi  # Should show your GPU
```

### Ollama (Optional — Native, Better Performance on macOS)

```bash
# macOS (native — uses Metal/MPS on Apple Silicon)
brew install ollama

# Linux (native)
curl -fsSL https://ollama.ai/install.sh | sh

# Windows (via installer)
# Download from: https://ollama.ai/download
```

---

## Quick Start

```bash
# Clone the repository
git clone https://github.com/sandbox_innovate/sandbox_innovate.git
cd sandbox_innovate/templates/local-docker

# CPU-only (no GPU required)
docker compose up -d

# GPU-enabled (NVIDIA required)
docker compose --profile gpu up -d

# Check status
docker compose ps

# View logs
docker compose logs -f

# Access services:
# Open WebUI (chat interface): http://localhost:3000
# JupyterLab:                  http://localhost:8888?token=sandbox
# Ollama API:                  http://localhost:11434

# Pull a model
docker exec -it ollama ollama pull llama3.1:8b
```

---

## Docker Compose Configuration

The [`templates/local-docker/docker-compose.yml`](../../templates/local-docker/docker-compose.yml) file provides the full configuration. Here's a walkthrough of key settings:

### Service: Ollama

```yaml
ollama:
  image: ollama/ollama:latest
  container_name: ollama
  restart: unless-stopped
  ports:
    - "11434:11434"
  volumes:
    - ollama_models:/root/.ollama   # Persist downloaded models
  networks:
    - sandbox_net
  # GPU profile (activated with --profile gpu)
  profiles: ["gpu"]
  deploy:
    resources:
      reservations:
        devices:
          - driver: nvidia
            count: 1
            capabilities: [gpu]
```

### Service: Open WebUI

```yaml
open-webui:
  image: ghcr.io/open-webui/open-webui:main
  container_name: open-webui
  restart: unless-stopped
  ports:
    - "3000:8080"
  environment:
    - OLLAMA_BASE_URL=http://ollama:11434
    - WEBUI_SECRET_KEY=change-me-in-production
  volumes:
    - open_webui_data:/app/backend/data
  networks:
    - sandbox_net
  depends_on:
    - ollama
```

### Service: JupyterLab

```yaml
jupyterlab:
  image: jupyter/scipy-notebook:latest
  container_name: jupyterlab
  restart: unless-stopped
  ports:
    - "8888:8888"
  environment:
    - JUPYTER_ENABLE_LAB=yes
    - JUPYTER_TOKEN=sandbox
    - JUPYTER_ALLOW_ORIGIN=*
  volumes:
    - ./notebooks:/home/jovyan/work      # Your notebooks
    - ollama_models:/home/jovyan/.ollama:ro  # Read model list
  networks:
    - sandbox_net
  command: >
    start-notebook.sh
    --NotebookApp.token='sandbox'
    --NotebookApp.ip='0.0.0.0'
```

### Customizing with Override File

Create `docker-compose.override.yml` to add local customizations without modifying the main file:

```yaml
# docker-compose.override.yml
services:
  jupyterlab:
    volumes:
      - /path/to/your/datasets:/home/jovyan/data:ro
      - /path/to/your/models:/home/jovyan/models:ro
    environment:
      - HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}

  ollama:
    environment:
      - OLLAMA_NUM_PARALLEL=2   # Run 2 models simultaneously
      - OLLAMA_MAX_LOADED_MODELS=2
```

---

## GPU Passthrough Configuration

### NVIDIA GPU

```yaml
# In docker-compose.yml under the service:
deploy:
  resources:
    reservations:
      devices:
        - driver: nvidia
          count: 1        # Number of GPUs (use "all" for all GPUs)
          capabilities: [gpu]
```

Verify GPU is accessible inside the container:

```bash
docker exec -it ollama nvidia-smi
# Should show: NVIDIA GPU name, driver version, memory usage
```

### AMD ROCm GPU

Use the ROCm-enabled Ollama image:

```bash
# Use Ollama ROCm image
docker run -d \
  --name ollama-rocm \
  --device /dev/kfd \
  --device /dev/dri \
  --group-add video \
  --group-add render \
  -v ollama_models:/root/.ollama \
  -p 11434:11434 \
  ollama/ollama:rocm
```

### Apple Silicon (No Docker GPU Passthrough — Use Native)

Docker Desktop on Apple Silicon does NOT pass through GPU/Metal to containers. For best performance:

```bash
# Use native Ollama (uses Metal/MPS automatically)
ollama serve &
ollama pull llama3.1:8b
ollama run llama3.1:8b

# Still use Docker for JupyterLab + Open WebUI
docker compose up -d jupyterlab open-webui

# In Open WebUI, set Ollama URL to: http://host.docker.internal:11434
```

---

## Security Configuration

### Network Isolation

By default, the sandbox network is **bridge** mode and has internet access (needed for model downloads). For air-gapped experimentation:

```yaml
# docker-compose.override.yml — isolate from internet
networks:
  sandbox_net:
    driver: bridge
    internal: true    # Blocks internet access entirely

  # Separate network for Ollama model downloads (internet-connected)
  ollama_external:
    driver: bridge

services:
  ollama:
    networks:
      - sandbox_net
      - ollama_external  # Allow internet for model downloads only
  jupyterlab:
    networks:
      - sandbox_net      # Internet blocked
  open-webui:
    networks:
      - sandbox_net      # Internet blocked
```

### JupyterLab Token

The default token `sandbox` is for local development only. For shared environments:

```bash
# Generate a strong token
JUPYTER_TOKEN=$(openssl rand -hex 32)
echo "JUPYTER_TOKEN=$JUPYTER_TOKEN" >> .env

# Reference in docker-compose.yml:
environment:
  - JUPYTER_TOKEN=${JUPYTER_TOKEN}
```

### Container Security Hardening

```yaml
# docker-compose.override.yml — add security constraints
services:
  jupyterlab:
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - SETUID
      - SETGID
    mem_limit: 8g
    memswap_limit: 8g
    cpus: "4.0"
```

### Secrets Management (Local)

```bash
# Create .env file (never commit to git)
cat > .env << 'EOF'
HUGGING_FACE_HUB_TOKEN=hf_your_token
ANTHROPIC_API_KEY=sk-ant-your_key
OPENAI_API_KEY=sk-your_key
JUPYTER_TOKEN=your-strong-random-token
WEBUI_SECRET_KEY=your-strong-random-secret
EOF

# Add .env to .gitignore
echo ".env" >> .gitignore
echo "*.env" >> .gitignore
```

---

## Running AI Models (Ollama, vLLM)

### Ollama

Ollama is the easiest way to run local models. It handles model downloading, GPU management, and serving:

```bash
# List available models
curl http://localhost:11434/api/tags | python3 -m json.tool

# Pull a model
docker exec -it ollama ollama pull llama3.1:8b
docker exec -it ollama ollama pull mistral:7b
docker exec -it ollama ollama pull phi3:mini
docker exec -it ollama ollama pull nomic-embed-text   # For embeddings

# Run via API
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.1:8b",
  "prompt": "What is the capital of France?",
  "stream": false
}' | python3 -m json.tool

# Use OpenAI-compatible API
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Using Ollama from JupyterLab

```python
# In a JupyterLab notebook
import requests

# Chat completion
response = requests.post(
    "http://ollama:11434/api/generate",
    json={
        "model": "llama3.1:8b",
        "prompt": "Explain transformers in ML in 3 sentences",
        "stream": False
    }
)
print(response.json()["response"])

# Or use the OpenAI client (OpenAI-compatible endpoint)
from openai import OpenAI

client = OpenAI(
    base_url="http://ollama:11434/v1",
    api_key="ollama"  # Ollama doesn't require a real key
)

response = client.chat.completions.create(
    model="llama3.1:8b",
    messages=[{"role": "user", "content": "Write a Python function to calculate Fibonacci numbers"}]
)
print(response.choices[0].message.content)
```

### vLLM (High-Throughput Serving — GPU Required)

For higher-throughput inference, add vLLM to your compose setup:

```yaml
# docker-compose.override.yml
services:
  vllm:
    image: vllm/vllm-openai:latest
    container_name: vllm
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - huggingface_cache:/root/.cache/huggingface
    environment:
      - HUGGING_FACE_HUB_TOKEN=${HUGGING_FACE_HUB_TOKEN}
    command: >
      --model mistralai/Mistral-7B-Instruct-v0.3
      --dtype auto
      --api-key vllm-sandbox
    networks:
      - sandbox_net
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]

volumes:
  huggingface_cache:
```

---

## Validation Tests

```bash
# 1. All services running
docker compose ps
# Expected: ollama, open-webui, jupyterlab all "Up"

# 2. Ollama API responding
curl -s http://localhost:11434/api/version | python3 -m json.tool
# Expected: {"version":"..."}

# 3. Ollama generates text
docker exec -it ollama ollama run phi3:mini "Say hello" 2>/dev/null | head -1
# Expected: Some greeting text

# 4. JupyterLab accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/login
# Expected: 200 or 302

# 5. Open WebUI accessible
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
# Expected: 200

# 6. GPU accessible in Ollama (if GPU setup)
docker exec -it ollama nvidia-smi 2>/dev/null | grep -q "NVIDIA" && \
  echo "✅ GPU accessible" || echo "⚠️ No GPU (CPU mode)"

# 7. Network isolation test (if using internal network)
docker exec -it jupyterlab curl -s --connect-timeout 2 https://google.com && \
  echo "⚠️ Internet accessible" || echo "✅ Internet blocked (isolated mode)"
```

---

## Troubleshooting

### Issue: Out of memory (OOM) when running models

**Solutions**:
1. Use a more quantized version: `ollama pull llama3.1:8b:q4_0` instead of full precision
2. Increase Docker Desktop memory: Settings → Resources → Memory (set to 16+ GB)
3. Use a smaller model: `phi3:mini` (3.8B) instead of `llama3.1:8b`
4. Set `OLLAMA_MAX_LOADED_MODELS=1` to ensure only one model is loaded at a time

### Issue: GPU not detected by Ollama

**Solutions**:
1. Verify NVIDIA Container Toolkit is installed: `docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi`
2. Ensure Ollama service uses `--profile gpu`: `docker compose --profile gpu up -d ollama`
3. Check NVIDIA driver is loaded: `nvidia-smi` on the host
4. On Windows WSL2: ensure NVIDIA CUDA on WSL driver is installed (not the Linux driver)

### Issue: Open WebUI can't connect to Ollama

**Solutions**:
1. Verify Ollama is running: `curl http://localhost:11434/api/tags`
2. Check network connectivity between containers: `docker exec open-webui curl http://ollama:11434/api/tags`
3. Ensure `OLLAMA_BASE_URL=http://ollama:11434` is set in Open WebUI environment
4. Check both services are on the same Docker network: `docker network inspect local-docker_sandbox_net`

### Issue: JupyterLab shows wrong token

**Solutions**:
1. Check the configured token: `docker exec jupyterlab jupyter server list`
2. Reset token: `docker compose restart jupyterlab`
3. Access with explicit token: `http://localhost:8888?token=sandbox`

### Issue: Volume permissions denied

**Solutions**:
```bash
# Fix notebook directory permissions
sudo chown -R 1000:1000 ./notebooks

# Or set permissions in compose
services:
  jupyterlab:
    user: root  # Temporary — not recommended for production
```
