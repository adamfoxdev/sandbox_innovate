# Developer Experience Guide

This guide covers the full AI developer toolkit — from installing tools and running models efficiently to versioning experiments and integrating with CI/CD pipelines.

---

## Table of Contents

- [Installing AI Tools](#installing-ai-tools)
- [Running Models Safely](#running-models-safely)
- [Using GPUs Efficiently](#using-gpus-efficiently)
- [Versioning Experiments](#versioning-experiments)
- [Reproducible Environments](#reproducible-environments)
- [Integrating with CI/CD](#integrating-with-cicd)

---

## Installing AI Tools

### Ollama — Local LLM Runtime

Ollama is the easiest way to run LLMs locally. It handles model downloads, GPU management, and provides a REST API.

```bash
# Linux / macOS
curl -fsSL https://ollama.ai/install.sh | sh

# macOS via Homebrew
brew install ollama

# Start server
ollama serve &

# Pull and run models
ollama pull llama3.1:8b
ollama pull mistral:7b-instruct
ollama pull nomic-embed-text     # Text embeddings
ollama pull llava:7b             # Vision + language model

# Interactive chat
ollama run llama3.1:8b

# API usage
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.1:8b",
  "prompt": "Explain retrieval-augmented generation in one paragraph",
  "stream": false
}'
```

### vLLM — High-Throughput LLM Serving

vLLM uses PagedAttention for 20–30× higher throughput than naive inference:

```bash
pip install vllm

# Start server
python -m vllm.entrypoints.openai.api_server \
  --model mistralai/Mistral-7B-Instruct-v0.3 \
  --port 8000 \
  --dtype auto \
  --max-model-len 4096

# Test
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistralai/Mistral-7B-Instruct-v0.3",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Hugging Face Transformers

```bash
pip install transformers accelerate datasets tokenizers

# Download and cache a model
python3 << 'EOF'
from transformers import AutoModelForCausalLM, AutoTokenizer
import torch

model_name = "microsoft/phi-2"
tokenizer = AutoTokenizer.from_pretrained(model_name)
model = AutoModelForCausalLM.from_pretrained(
    model_name,
    torch_dtype=torch.float16,
    device_map="auto"  # Automatically use available GPU
)

inputs = tokenizer("The future of AI is", return_tensors="pt").to(model.device)
with torch.no_grad():
    outputs = model.generate(**inputs, max_new_tokens=100)
print(tokenizer.decode(outputs[0], skip_special_tokens=True))
EOF
```

### LangChain

```bash
pip install langchain langchain-community langchain-ollama langchain-openai

# Example: Simple RAG pipeline with Ollama
python3 << 'EOF'
from langchain_ollama import OllamaLLM, OllamaEmbeddings
from langchain_community.vectorstores import FAISS
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain.chains import RetrievalQA

# Initialize models
llm = OllamaLLM(model="llama3.1:8b", base_url="http://localhost:11434")
embeddings = OllamaEmbeddings(model="nomic-embed-text", base_url="http://localhost:11434")

# Create a simple knowledge base
texts = [
    "LangChain is a framework for building LLM-powered applications.",
    "RAG stands for Retrieval-Augmented Generation.",
    "Vector databases store embeddings for semantic search.",
]
text_splitter = RecursiveCharacterTextSplitter(chunk_size=200, chunk_overlap=20)
docs = text_splitter.create_documents(texts)

# Build vector store
vectorstore = FAISS.from_documents(docs, embeddings)

# RAG chain
qa_chain = RetrievalQA.from_chain_type(
    llm=llm,
    retriever=vectorstore.as_retriever(search_kwargs={"k": 2})
)

result = qa_chain.invoke("What is RAG?")
print(result["result"])
EOF
```

### LlamaIndex

```bash
pip install llama-index llama-index-llms-ollama llama-index-embeddings-ollama

# Example: Document Q&A
python3 << 'EOF'
from llama_index.core import VectorStoreIndex, SimpleDirectoryReader
from llama_index.llms.ollama import Ollama
from llama_index.embeddings.ollama import OllamaEmbedding
from llama_index.core import Settings

# Configure local models
Settings.llm = Ollama(model="llama3.1:8b", base_url="http://localhost:11434", request_timeout=120.0)
Settings.embed_model = OllamaEmbedding(model_name="nomic-embed-text", base_url="http://localhost:11434")

# Load documents
documents = SimpleDirectoryReader("./data/documents").load_data()
index = VectorStoreIndex.from_documents(documents)

# Query
query_engine = index.as_query_engine()
response = query_engine.query("What are the main topics covered?")
print(response)
EOF
```

---

## Running Models Safely

### Data Classification Before Model Use

Before running any data through a model, classify it:

```python
# data_safety.py — simple data classification helper
from enum import Enum
from typing import Optional

class DataTier(Enum):
    PUBLIC = 1
    INTERNAL = 2
    CONFIDENTIAL = 3
    RESTRICTED = 4

def check_model_allowed(data_tier: DataTier, model_endpoint: str) -> tuple[bool, Optional[str]]:
    """Check if using a model with given data tier is allowed."""
    external_apis = ["api.openai.com", "api.anthropic.com", "api.cohere.ai"]
    is_external = any(api in model_endpoint for api in external_apis)

    if data_tier == DataTier.RESTRICTED:
        return False, "RESTRICTED data requires CISO approval before any AI use"
    if data_tier == DataTier.CONFIDENTIAL and is_external:
        return False, "CONFIDENTIAL data cannot be sent to external APIs — use local model"
    if data_tier == DataTier.INTERNAL and is_external:
        return False, "INTERNAL data requires DLP review before using external APIs"

    return True, None

# Usage
allowed, reason = check_model_allowed(DataTier.CONFIDENTIAL, "http://localhost:11434")
if not allowed:
    raise PermissionError(f"Data safety violation: {reason}")
```

### Rate Limiting and Resource Controls

```python
# rate_limiter.py — prevent runaway inference costs/compute
import time
import functools
from typing import Callable

def rate_limit(calls_per_minute: int = 60):
    """Decorator to rate-limit LLM API calls."""
    min_interval = 60.0 / calls_per_minute
    last_called = [0.0]

    def decorator(func: Callable):
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            elapsed = time.monotonic() - last_called[0]
            wait_time = min_interval - elapsed
            if wait_time > 0:
                time.sleep(wait_time)
            last_called[0] = time.monotonic()
            return func(*args, **kwargs)
        return wrapper
    return decorator

@rate_limit(calls_per_minute=30)
def generate_with_ollama(prompt: str, model: str = "llama3.1:8b") -> str:
    import requests
    response = requests.post(
        "http://localhost:11434/api/generate",
        json={"model": model, "prompt": prompt, "stream": False},
        timeout=120
    )
    return response.json()["response"]
```

---

## Using GPUs Efficiently

### Monitor GPU Utilization

```bash
# Real-time GPU monitoring
watch -n 1 nvidia-smi

# Log GPU usage to file
nvidia-smi dmon -s u -d 5 -f gpu_utilization.log &

# Python-based monitoring
pip install gpustat
gpustat --watch
```

### Optimize VRAM Usage in PyTorch

```python
import torch
from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

# 4-bit quantization — reduces VRAM by 75% with minimal quality loss
bnb_config = BitsAndBytesConfig(
    load_in_4bit=True,
    bnb_4bit_use_double_quant=True,
    bnb_4bit_quant_type="nf4",
    bnb_4bit_compute_dtype=torch.bfloat16,
)

model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Meta-Llama-3.1-8B",
    quantization_config=bnb_config,
    device_map="auto"
)

# Enable Flash Attention 2 (2–4× faster, ~50% less VRAM)
# Requires: pip install flash-attn
model = AutoModelForCausalLM.from_pretrained(
    "meta-llama/Meta-Llama-3.1-8B",
    torch_dtype=torch.bfloat16,
    attn_implementation="flash_attention_2",
    device_map="auto"
)

# Mixed precision inference
with torch.autocast(device_type="cuda", dtype=torch.bfloat16):
    outputs = model.generate(inputs, max_new_tokens=200)

# Clear VRAM between experiments
del model
torch.cuda.empty_cache()
import gc; gc.collect()
```

### Batch Processing for Throughput

```python
# Process multiple prompts in parallel for efficiency
from transformers import pipeline
import torch

# Use pipeline with batching
pipe = pipeline(
    "text-generation",
    model="microsoft/phi-2",
    device=0,  # GPU 0
    torch_dtype=torch.float16,
    batch_size=8  # Process 8 prompts at a time
)

prompts = [
    "Summarize: " + doc
    for doc in your_documents  # List of documents to summarize
]

results = pipe(prompts, max_new_tokens=200, do_sample=False)
summaries = [r[0]['generated_text'] for r in results]
```

---

## Versioning Experiments

### MLflow — Experiment Tracking

```bash
pip install mlflow

# Start MLflow UI
mlflow ui --host 0.0.0.0 --port 5000 &
# Access at: http://localhost:5000
```

```python
import mlflow
import mlflow.transformers
import json

# Configure tracking server
mlflow.set_tracking_uri("http://localhost:5000")
mlflow.set_experiment("llm-evaluation")

with mlflow.start_run(run_name="llama3.1-8b-baseline"):
    # Log parameters
    mlflow.log_params({
        "model": "llama3.1:8b",
        "temperature": 0.7,
        "max_tokens": 500,
        "dataset": "eval_set_v1",
    })

    # Run evaluation
    results = evaluate_model(model_name="llama3.1:8b", dataset="eval_set_v1")

    # Log metrics
    mlflow.log_metrics({
        "accuracy": results["accuracy"],
        "avg_latency_ms": results["avg_latency"],
        "throughput_tps": results["tokens_per_second"],
        "bleu_score": results["bleu"],
    })

    # Log artifacts (model outputs, config files)
    mlflow.log_dict(results["outputs"], "model_outputs.json")
    mlflow.log_artifact("evaluation_config.yaml")

    # Tag for easy filtering
    mlflow.set_tags({
        "model_family": "llama",
        "quantization": "none",
        "hardware": "nvidia-t4",
    })
```

### DVC — Data Version Control

```bash
pip install dvc dvc-s3  # or dvc-azure, dvc-gs

# Initialize DVC in your project
cd your-project
git init
dvc init
git add .dvc
git commit -m "Initialize DVC"

# Configure remote storage
dvc remote add -d myremote s3://sandbox-datasets-${ACCOUNT_ID}/dvc-cache
# Or for Azure:
# dvc remote add -d myremote azure://sandbox-datasets/dvc-cache

# Track datasets
dvc add data/training_dataset.jsonl
git add data/training_dataset.jsonl.dvc data/.gitignore
git commit -m "Track training dataset v1"

# Push data to remote
dvc push

# Pull data on a new machine
git clone your-repo && dvc pull
```

### Experiment Configuration with Hydra

```bash
pip install hydra-core omegaconf
```

```yaml
# config/experiment.yaml
model:
  name: llama3.1:8b
  temperature: 0.7
  max_tokens: 500

dataset:
  name: eval_set_v1
  split: test
  max_samples: 100

evaluation:
  metrics: [accuracy, bleu, bertscore]
  batch_size: 8
```

```python
import hydra
from omegaconf import DictConfig

@hydra.main(version_base=None, config_path="config", config_name="experiment")
def run_experiment(cfg: DictConfig) -> None:
    import mlflow
    with mlflow.start_run():
        mlflow.log_params(dict(cfg.model) | dict(cfg.dataset))
        results = evaluate(cfg)
        mlflow.log_metrics(results)

if __name__ == "__main__":
    run_experiment()
```

---

## Reproducible Environments

### Using `uv` for Fast Python Environment Management

```bash
# Install uv (much faster than pip)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and activate environment
uv venv .venv --python 3.11
source .venv/bin/activate  # Linux/macOS
# .venv\Scripts\activate  # Windows

# Install dependencies (uses pyproject.toml or requirements.txt)
uv pip install -r requirements.txt

# Pin exact versions for reproducibility
uv pip freeze > requirements.lock
```

### `requirements.txt` for AI Projects

```
# requirements.txt
transformers==4.44.2
torch==2.4.0
accelerate==0.33.0
bitsandbytes==0.43.3
datasets==2.21.0
evaluate==0.4.3
langchain==0.2.16
langchain-community==0.2.17
llama-index==0.11.3
mlflow==2.15.1
dvc==3.53.0
jupyter==1.1.1
ipywidgets==8.1.3
pandas==2.2.2
numpy==1.26.4
matplotlib==3.9.2
seaborn==0.13.2
tqdm==4.66.5
python-dotenv==1.0.1
```

### Dev Container for Maximum Reproducibility

The VS Code Dev Container in `templates/vscode-devcontainer/` provides a fully reproducible development environment that works identically across all team members' machines. See [vscode-devcontainer README](../templates/vscode-devcontainer/.devcontainer/).

---

## Integrating with CI/CD

### GitHub Actions — Automated Model Evaluation

```yaml
# .github/workflows/model-eval.yml
name: Model Evaluation

on:
  pull_request:
    paths:
      - 'prompts/**'
      - 'evaluation/**'

jobs:
  evaluate:
    runs-on: ubuntu-latest
    # Or: runs-on: self-hosted  (use a self-hosted runner with GPU for real inference)

    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Start Ollama
        run: |
          curl -fsSL https://ollama.ai/install.sh | sh
          ollama serve &
          sleep 5
          ollama pull phi3:mini  # Use small model for CI

      - name: Run evaluation
        run: python evaluation/run_eval.py --model phi3:mini --dataset test_set_small
        env:
          MLFLOW_TRACKING_URI: ${{ secrets.MLFLOW_TRACKING_URI }}

      - name: Check evaluation thresholds
        run: |
          python evaluation/check_thresholds.py \
            --min-accuracy 0.80 \
            --max-latency 5000

      - name: Upload results
        uses: actions/upload-artifact@v4
        with:
          name: evaluation-results
          path: evaluation/results/
```

### GitLab CI — Sandbox Provisioning

```yaml
# .gitlab-ci.yml
stages:
  - provision
  - evaluate
  - destroy

provision-sandbox:
  stage: provision
  image: hashicorp/terraform:1.7
  script:
    - cd templates/aws-ec2
    - terraform init
    - terraform apply -auto-approve -var="instance_type=g4dn.xlarge"
    - terraform output -raw instance_id > /tmp/instance_id
  artifacts:
    paths:
      - templates/aws-ec2/terraform.tfstate
      - /tmp/instance_id
  when: manual

run-evaluation:
  stage: evaluate
  script:
    - INSTANCE_ID=$(cat /tmp/instance_id)
    - aws ssm start-session --target $INSTANCE_ID ...

destroy-sandbox:
  stage: destroy
  image: hashicorp/terraform:1.7
  script:
    - cd templates/aws-ec2
    - terraform destroy -auto-approve
  when: always  # Always clean up
  needs: [run-evaluation]
```

### Pre-commit Hooks for Safety

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/Yelp/detect-secrets
    rev: v1.5.0
    hooks:
      - id: detect-secrets
        args: ['--baseline', '.secrets.baseline']

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.6.0
    hooks:
      - id: check-added-large-files
        args: ['--maxkb=10240']  # Block files > 10 MB (catches accidental dataset commits)
      - id: check-json
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
```

```bash
# Install pre-commit hooks
pip install pre-commit detect-secrets
pre-commit install
detect-secrets scan > .secrets.baseline
git add .pre-commit-config.yaml .secrets.baseline
git commit -m "chore: add pre-commit hooks for security"
```
