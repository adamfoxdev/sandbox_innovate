# Local AI Sandbox — Docker Compose

This Docker Compose template spins up a complete local AI sandbox with:
- **Ollama** — local LLM runtime with GPU support
- **Open WebUI** — browser-based chat interface for Ollama
- **JupyterLab** — GPU-accelerated notebook environment

---

## Quick Start

### CPU Mode (No GPU Required)

```bash
docker compose up -d
```

### GPU Mode (NVIDIA GPU Required)

```bash
docker compose --profile gpu up -d
```

### Check Status

```bash
docker compose ps
docker compose logs -f
```

## Access Services

| Service | URL | Notes |
|---------|-----|-------|
| Open WebUI | http://localhost:3000 | Create account on first visit |
| JupyterLab | http://localhost:8888 | Token: `sandbox` |
| Ollama API | http://localhost:11434 | REST API |

## Pull Your First Model

```bash
# Small, fast model (best for CPU)
docker exec -it ollama ollama pull phi3:mini

# Good general-purpose model
docker exec -it ollama ollama pull llama3.1:8b

# Embeddings model (for RAG pipelines)
docker exec -it ollama ollama pull nomic-embed-text
```

## Stop the Sandbox

```bash
docker compose down          # Stop containers, keep volumes
docker compose down -v       # Stop containers AND delete all data
```

## Configuration

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

Key settings:
- `JUPYTER_TOKEN` — change from default `sandbox` for shared use
- `OLLAMA_NUM_PARALLEL` — number of simultaneous model requests (default: 1)
- `HF_TOKEN` — Hugging Face API token for downloading gated models

## GPU Requirements

- NVIDIA driver >= 520
- NVIDIA Container Toolkit installed
- Run: `docker run --rm --gpus all nvidia/cuda:12.1.0-base-ubuntu22.04 nvidia-smi` to verify
