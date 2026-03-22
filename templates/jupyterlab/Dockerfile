# Secure JupyterLab Dockerfile
# Base: Jupyter scipy-notebook (Ubuntu 22.04)
# Adds: AI/ML packages, security hardening, GPU support

ARG BASE_IMAGE=quay.io/jupyter/scipy-notebook
ARG BASE_TAG=2024-09-02

FROM ${BASE_IMAGE}:${BASE_TAG}

# Switch to root for installation
USER root

# ── System Dependencies ─────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools (needed for some Python packages)
    build-essential \
    gcc \
    g++ \
    cmake \
    # Git for version control
    git \
    git-lfs \
    # Useful CLI tools
    curl \
    wget \
    unzip \
    jq \
    htop \
    # Clean up
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Python AI/ML Packages ───────────────────────────────────────────────────
# Switch back to jovyan user for pip installs
USER ${NB_UID}

# Install PyTorch (with CUDA support — will fall back to CPU if no GPU)
RUN pip install --no-cache-dir \
    torch==2.4.0 \
    torchvision==0.19.0 \
    torchaudio==2.4.0 \
    --index-url https://download.pytorch.org/whl/cu121 \
    && pip install --no-cache-dir \
    # Hugging Face ecosystem
    transformers==4.44.2 \
    accelerate==0.33.0 \
    datasets==2.21.0 \
    tokenizers==0.19.1 \
    huggingface_hub==0.24.5 \
    peft==0.12.0 \
    trl==0.9.6 \
    # Quantization (4-bit and 8-bit)
    bitsandbytes==0.43.3 \
    # LangChain ecosystem
    langchain==0.2.16 \
    langchain-community==0.2.17 \
    langchain-ollama==0.1.3 \
    langchain-openai==0.1.23 \
    # LlamaIndex
    llama-index==0.11.3 \
    llama-index-llms-ollama==0.3.2 \
    llama-index-embeddings-ollama==0.3.1 \
    # Vector stores
    faiss-cpu==1.8.0 \
    chromadb==0.5.5 \
    # Experiment tracking
    mlflow==2.15.1 \
    # Data versioning
    dvc==3.53.0 \
    # Evaluation
    evaluate==0.4.3 \
    rouge_score==0.1.2 \
    nltk==3.9.1 \
    # Utilities
    python-dotenv==1.0.1 \
    tqdm==4.66.5 \
    rich==13.7.1 \
    typer==0.12.5 \
    requests==2.32.3 \
    httpx==0.27.2 \
    aiohttp==3.10.5 \
    # Jupyter extensions
    ipywidgets==8.1.3 \
    jupyterlab-git==0.50.1 \
    jupyterlab-lsp==5.1.0 \
    python-lsp-server==1.12.0

# ── Security and Privacy Tools ──────────────────────────────────────────────
RUN pip install --no-cache-dir \
    # PII detection and anonymization
    presidio-analyzer==2.2.354 \
    presidio-anonymizer==2.2.354 \
    # Secret detection
    detect-secrets==1.5.0

# Download spacy model for Presidio NLP
RUN python -m spacy download en_core_web_lg --quiet 2>/dev/null || \
    python -m spacy download en_core_web_sm

# ── JupyterLab Configuration ────────────────────────────────────────────────
USER root

# Create workspace directory with correct permissions
RUN mkdir -p /workspace \
    && chown ${NB_UID}:${NB_GID} /workspace

# JupyterLab server configuration
COPY --chown=${NB_UID}:${NB_GID} jupyter_server_config.py /home/jovyan/.jupyter/

# Set environment variables
ENV JUPYTER_ENABLE_LAB=yes \
    NOTEBOOK_DIR=/workspace \
    # Disable tracking
    DO_NOT_TRACK=1 \
    ANONYMIZED_TELEMETRY=0 \
    # HuggingFace cache location
    HF_HOME=/workspace/.cache/huggingface \
    # Torch compile cache
    TORCH_HOME=/workspace/.cache/torch

# ── Security Hardening ───────────────────────────────────────────────────────
# Remove setuid/setgid bits from binaries
RUN find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -not -path "*/proc/*" \
    -exec chmod -s {} \; 2>/dev/null || true

# Switch back to non-root user
USER ${NB_UID}

# Set working directory
WORKDIR /workspace

# ── Health Check ────────────────────────────────────────────────────────────
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8888/api || exit 1

# ── Startup ─────────────────────────────────────────────────────────────────
EXPOSE 8888

CMD ["start-notebook.py", \
     "--NotebookApp.ip=0.0.0.0", \
     "--NotebookApp.open_browser=False", \
     "--NotebookApp.allow_origin=*", \
     "--ServerApp.root_dir=/workspace"]
