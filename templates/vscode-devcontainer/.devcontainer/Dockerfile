# VS Code Dev Container — AI Sandbox Dockerfile
# Provides a reproducible Python 3.11 development environment
# with CUDA support, common AI/ML packages, and development tools.

ARG PYTHON_VERSION=3.11
ARG CUDA_VERSION=12.1
ARG UBUNTU_VERSION=22.04

# ── Base Image ───────────────────────────────────────────────────────────────
# Use CUDA base for GPU support. Remove CUDA base if not using GPU.
FROM nvidia/cuda:${CUDA_VERSION}.0-cudnn8-devel-ubuntu${UBUNTU_VERSION}
# Alternative (CPU only): FROM python:${PYTHON_VERSION}-slim-bookworm

# ── Build Arguments ──────────────────────────────────────────────────────────
ARG PYTHON_VERSION=3.11
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# ── Environment Variables ────────────────────────────────────────────────────
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    # CUDA settings
    CUDA_HOME=/usr/local/cuda \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    PATH=/usr/local/cuda/bin:${PATH} \
    # Python path
    PYTHONPATH=/workspace:${PYTHONPATH}

# ── System Dependencies ──────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-dev \
    python${PYTHON_VERSION}-venv \
    python3-pip \
    # Build tools
    build-essential \
    gcc \
    g++ \
    cmake \
    ninja-build \
    pkg-config \
    # Git and version control
    git \
    git-lfs \
    # Shell and utilities
    bash \
    bash-completion \
    zsh \
    curl \
    wget \
    unzip \
    jq \
    tree \
    htop \
    nvtop \
    tmux \
    # Editor
    vim \
    nano \
    # Networking
    net-tools \
    iputils-ping \
    dnsutils \
    # Development
    make \
    ca-certificates \
    gnupg \
    lsb-release \
    # For Pillow / image processing
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    # For audio processing
    libsndfile1 \
    ffmpeg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ── Create Non-Root User ─────────────────────────────────────────────────────
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    --shell /bin/bash \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# ── Python Version Setup ─────────────────────────────────────────────────────
# Set python${PYTHON_VERSION} as the default python3
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1 \
    && update-alternatives --install /usr/bin/python python /usr/bin/python${PYTHON_VERSION} 1 \
    && python3 -m pip install --upgrade pip setuptools wheel

# ── Install uv (fast Python package manager) ─────────────────────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | bash
ENV PATH="/root/.cargo/bin:${PATH}"

# ── Core Python Packages ─────────────────────────────────────────────────────
RUN pip install --no-cache-dir \
    # PyTorch with CUDA support
    torch==2.4.0 \
    torchvision==0.19.0 \
    torchaudio==2.4.0 \
    --index-url https://download.pytorch.org/whl/cu121

RUN pip install --no-cache-dir \
    # Hugging Face ecosystem
    transformers==4.44.2 \
    accelerate==0.33.0 \
    datasets==2.21.0 \
    tokenizers==0.19.1 \
    huggingface_hub==0.24.5 \
    peft==0.12.0 \
    trl==0.9.6 \
    bitsandbytes==0.43.3 \
    # LangChain
    langchain==0.2.16 \
    langchain-community==0.2.17 \
    langchain-ollama==0.1.3 \
    langchain-openai==0.1.23 \
    # LlamaIndex
    llama-index==0.11.3 \
    # OpenAI client
    openai==1.44.1 \
    anthropic==0.34.0 \
    # Vector databases
    faiss-cpu==1.8.0 \
    chromadb==0.5.5 \
    # Experiment tracking
    mlflow==2.15.1 \
    # Data processing
    pandas==2.2.2 \
    numpy==1.26.4 \
    polars==1.5.0 \
    pyarrow==17.0.0 \
    # Visualization
    matplotlib==3.9.2 \
    seaborn==0.13.2 \
    plotly==5.24.0 \
    # Jupyter
    jupyter==1.1.1 \
    jupyterlab==4.2.5 \
    ipywidgets==8.1.3 \
    ipykernel==6.29.5 \
    nbformat==5.10.4 \
    # Development tools
    ruff==0.6.3 \
    mypy==1.11.2 \
    pytest==8.3.2 \
    pytest-asyncio==0.23.8 \
    # Utilities
    python-dotenv==1.0.1 \
    rich==13.7.1 \
    typer==0.12.5 \
    tqdm==4.66.5 \
    httpx==0.27.2 \
    aiohttp==3.10.5 \
    pydantic==2.8.2 \
    # Security
    detect-secrets==1.5.0 \
    presidio-analyzer==2.2.354 \
    presidio-anonymizer==2.2.354

# ── Install Ollama (for local inference) ─────────────────────────────────────
RUN curl -fsSL https://ollama.ai/install.sh | sh

# ── Create Workspace ─────────────────────────────────────────────────────────
RUN mkdir -p /workspace \
    && chown ${USER_UID}:${USER_GID} /workspace

# ── Switch to Non-Root User ──────────────────────────────────────────────────
USER ${USERNAME}

# Add user's local bin to PATH
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"

# ── User-Level Python Config ──────────────────────────────────────────────────
# Download spacy model for Presidio
RUN python3 -m spacy download en_core_web_sm 2>/dev/null || true

# ── Working Directory ────────────────────────────────────────────────────────
WORKDIR /workspace

# ── Labels ───────────────────────────────────────────────────────────────────
LABEL maintainer="sandbox_innovate" \
      description="VS Code Dev Container for secure AI sandbox development" \
      python.version="${PYTHON_VERSION}" \
      cuda.version="${CUDA_VERSION}"
