# Resources

A curated list of external resources for building, securing, and optimizing AI sandbox environments.

---

## Cloud Provider Documentation

### Azure

| Resource | Description | URL |
|----------|-------------|-----|
| Azure NC/NV VM Sizes | GPU-enabled virtual machine sizes and specs | https://docs.microsoft.com/azure/virtual-machines/sizes-gpu |
| Azure Virtual Network | VNet concepts and configuration | https://docs.microsoft.com/azure/virtual-network/ |
| Azure Key Vault | Secrets, keys, and certificate management | https://docs.microsoft.com/azure/key-vault/ |
| Managed Identities | Service identity without credentials | https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/ |
| Azure Pricing Calculator | Estimate costs before deploying | https://azure.microsoft.com/pricing/calculator/ |
| Azure AI Services | Managed AI/ML services | https://azure.microsoft.com/products/ai-services/ |
| Azure OpenAI Service | Enterprise GPT-4 with data privacy | https://azure.microsoft.com/products/ai-services/openai-service |
| Azure Spot VMs | Discounted interruptible VMs | https://azure.microsoft.com/pricing/spot/ |

### AWS

| Resource | Description | URL |
|----------|-------------|-----|
| EC2 GPU Instances | G4, G5, P3, P4, P5 instance details | https://aws.amazon.com/ec2/instance-types/g4/ |
| Amazon VPC | Virtual Private Cloud concepts | https://docs.aws.amazon.com/vpc/ |
| AWS IAM | Identity and Access Management | https://docs.aws.amazon.com/iam/ |
| AWS Secrets Manager | Managed secrets storage | https://docs.aws.amazon.com/secretsmanager/ |
| AWS Systems Manager | Session Manager for SSH-free access | https://docs.aws.amazon.com/systems-manager/ |
| AWS Pricing Calculator | Estimate cloud costs | https://calculator.aws |
| Spot Instance Advisor | Real-time spot interruption rates | https://aws.amazon.com/ec2/spot/instance-advisor/ |
| AWS Deep Learning AMIs | Pre-configured ML instances | https://aws.amazon.com/machine-learning/amis/ |
| Amazon Bedrock | Managed foundation models | https://aws.amazon.com/bedrock/ |

### GCP

| Resource | Description | URL |
|----------|-------------|-----|
| GCP GPU Machine Types | A2, G2, N1 + GPU configurations | https://cloud.google.com/compute/docs/gpus |
| VPC Networks | Virtual Private Cloud networking | https://cloud.google.com/vpc/docs/ |
| Cloud IAM | Identity and access management | https://cloud.google.com/iam/docs/ |
| Secret Manager | Managed secrets storage | https://cloud.google.com/secret-manager/docs/ |
| Identity-Aware Proxy | BeyondCorp access for VMs | https://cloud.google.com/iap/docs/ |
| GCP Pricing Calculator | Estimate costs | https://cloud.google.com/products/calculator |
| Preemptible VMs | Discounted interruptible VMs | https://cloud.google.com/compute/docs/instances/preemptible |
| Deep Learning VM Images | Pre-configured ML images | https://cloud.google.com/deep-learning-vm/ |
| Vertex AI | Managed ML platform | https://cloud.google.com/vertex-ai |

---

## Security Hardening Guides

| Resource | Description | URL |
|----------|-------------|-----|
| CIS Benchmarks | Configuration hardening for cloud and OS | https://www.cisecurity.org/cis-benchmarks |
| NIST AI Risk Management Framework | AI risk assessment framework | https://www.nist.gov/system/files/documents/2023/01/26/NIST.AI.100-1.pdf |
| OWASP Top 10 for LLMs | Security risks specific to LLM applications | https://owasp.org/www-project-top-10-for-large-language-model-applications/ |
| AWS Security Best Practices | Well-Architected Framework security pillar | https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/ |
| Azure Security Benchmark | Azure security baseline | https://docs.microsoft.com/security/benchmark/azure/ |
| GCP Security Best Practices | Google Cloud security foundations | https://cloud.google.com/security/best-practices |
| HashiCorp Vault | Open-source secrets management | https://developer.hashicorp.com/vault/docs |
| Docker Security | Securing Docker environments | https://docs.docker.com/engine/security/ |
| NVIDIA CUDA Security | Securing GPU environments | https://www.nvidia.com/en-us/security/ |

---

## AI Model Safety Best Practices

| Resource | Description | URL |
|----------|-------------|-----|
| Hugging Face Safety | Model safety and bias detection | https://huggingface.co/docs/hub/model-cards |
| Microsoft Responsible AI | Principles and practices | https://www.microsoft.com/responsible-ai |
| Google AI Principles | Google's AI guidelines | https://ai.google/responsibility/principles/ |
| Anthropic Model Card | Claude model safety documentation | https://www.anthropic.com/model-card |
| ModelScan | Scan ML models for malware | https://github.com/protectai/modelscan |
| Microsoft Presidio | PII detection and anonymization | https://microsoft.github.io/presidio/ |
| Guardrails AI | Output validation for LLMs | https://github.com/guardrails-ai/guardrails |
| LLM Guard | Security toolkit for LLM interactions | https://github.com/protectai/llm-guard |
| Garak | LLM vulnerability scanner | https://github.com/NVIDIA/garak |
| EU AI Act | EU regulation on artificial intelligence | https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:52021PC0206 |

---

## Cost Calculators

| Resource | Description | URL |
|----------|-------------|-----|
| Azure Pricing Calculator | Official Azure cost estimator | https://azure.microsoft.com/pricing/calculator/ |
| AWS Pricing Calculator | Official AWS cost estimator | https://calculator.aws |
| GCP Pricing Calculator | Official GCP cost estimator | https://cloud.google.com/products/calculator |
| Spot.io | Multi-cloud spot instance optimizer | https://spot.io |
| Infracost | IaC cost estimation for Terraform | https://www.infracost.io |
| Cloud Price Comparison | Compare pricing across clouds | https://cloudprice.net |

---

## GPU Benchmarking Resources

| Resource | Description | URL |
|----------|-------------|-----|
| LLM Inference Benchmark | Community GPU benchmark for LLMs | https://github.com/ggerganov/llama.cpp#performance |
| MLPerf Benchmarks | Industry standard ML benchmarks | https://mlcommons.org/benchmarks/ |
| Puget Systems GPU Benchmarks | Independent GPU testing | https://www.pugetsystems.com/labs/articles/ |
| GPU Benchmark Database | Comparative GPU performance | https://benchmarks.ul.com/resources/gpu-benchmark-charts |
| NVIDIA T4 vs A10G Comparison | Cloud GPU comparison | https://www.nvidia.com/content/dam/en-zz/Solutions/Data-Center/tesla-t4/t4-tensor-core-datasheet.pdf |
| LLM on CPU Benchmarks | llama.cpp CPU inference performance | https://github.com/ggerganov/llama.cpp#memorydisk-requirements |
| vLLM Benchmarks | vLLM throughput benchmarks | https://docs.vllm.ai/en/latest/performance/performance.html |

---

## Community Resources

### Forums and Communities

| Resource | Description | URL |
|----------|-------------|-----|
| Hugging Face Forums | Community for ML practitioners | https://discuss.huggingface.co |
| LangChain Discord | LangChain community | https://discord.gg/6adMQxSpJS |
| LocalLLaMA (Reddit) | Running LLMs locally | https://reddit.com/r/LocalLLaMA |
| MLOps Community | MLOps practitioners | https://mlops.community |
| AI Safety Forum | AI safety research discussion | https://www.alignmentforum.org |

### GitHub Repositories

| Repository | Description | URL |
|------------|-------------|-----|
| Ollama | Local LLM runtime | https://github.com/ollama/ollama |
| vLLM | High-throughput LLM serving | https://github.com/vllm-project/vllm |
| Open WebUI | Browser UI for Ollama | https://github.com/open-webui/open-webui |
| LangChain | LLM application framework | https://github.com/langchain-ai/langchain |
| LlamaIndex | Data framework for LLMs | https://github.com/run-llama/llama_index |
| MLflow | ML experiment tracking | https://github.com/mlflow/mlflow |
| DVC | Data version control | https://github.com/iterative/dvc |
| Transformers | Hugging Face model library | https://github.com/huggingface/transformers |
| llama.cpp | CPU-optimized inference | https://github.com/ggerganov/llama.cpp |
| text-generation-webui | Web UI for text generation | https://github.com/oobabooga/text-generation-webui |

### Learning Resources

| Resource | Description | URL |
|----------|-------------|-----|
| Fast.ai | Practical deep learning | https://course.fast.ai |
| Hugging Face Course | NLP and transformers | https://huggingface.co/course |
| DeepLearning.AI Short Courses | Practical AI courses | https://learn.deeplearning.ai |
| LangChain Academy | LangChain development | https://academy.langchain.com |
| Google ML Crash Course | ML fundamentals | https://developers.google.com/machine-learning/crash-course |
| Andrej Karpathy Neural Networks | Zero to hero series | https://karpathy.ai/zero-to-hero.html |

---

## Model Repositories

| Resource | Description | URL |
|----------|-------------|-----|
| Hugging Face Hub | Largest open model repository | https://huggingface.co/models |
| Ollama Library | Models optimized for Ollama | https://ollama.ai/library |
| GGUF Models (TheBloke) | Quantized models for llama.cpp | https://huggingface.co/TheBloke |
| Civitai | Image generation models | https://civitai.com |
| Open LLM Leaderboard | Model quality benchmarks | https://huggingface.co/spaces/HuggingFaceH4/open_llm_leaderboard |
