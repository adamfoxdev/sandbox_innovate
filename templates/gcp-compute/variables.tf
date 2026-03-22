variable "project_id" {
  description = "GCP project ID where sandbox resources will be created"
  type        = string
  # No default — must be explicitly set
}

variable "region" {
  description = "GCP region for all resources"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone for the compute instance"
  type        = string
  default     = "us-central1-a"
}

variable "project_name" {
  description = "Short project name used in resource naming (max 15 chars)"
  type        = string
  default     = "aisandbox"

  validation {
    condition     = length(var.project_name) <= 15 && can(regex("^[a-z][a-z0-9-]+$", var.project_name))
    error_message = "project_name must start with a letter, be lowercase alphanumeric/hyphens, max 15 chars."
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "dev", "staging"], var.environment)
    error_message = "environment must be one of: sandbox, dev, staging."
  }
}

variable "team_name" {
  description = "Team name for resource labeling"
  type        = string
  default     = "ai-team"
}

# --- Network Variables ---

variable "subnet_cidr" {
  description = "CIDR range for the sandbox subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr_ranges" {
  description = "IP CIDR ranges allowed to connect to the sandbox (corporate VPN, bastion)"
  type        = list(string)
  default     = []  # Empty = only IAP SSH allowed (recommended)
}

variable "enable_cloud_nat" {
  description = "Enable Cloud NAT for outbound internet access (needed for model downloads)"
  type        = bool
  default     = true
}

# --- Compute Variables ---

variable "machine_type" {
  description = "GCP machine type for the sandbox instance"
  type        = string
  default     = "n1-standard-4"

  # Common options:
  # n1-standard-4  - 4 vCPU, 15 GB RAM — use with GPU accelerator
  # n1-standard-8  - 8 vCPU, 30 GB RAM — use with GPU accelerator
  # g2-standard-4  - 4 vCPU, 16 GB RAM — includes NVIDIA L4 GPU
  # g2-standard-8  - 8 vCPU, 32 GB RAM — includes NVIDIA L4 GPU
  # a2-highgpu-1g  - 12 vCPU, 85 GB RAM — includes NVIDIA A100 GPU
  # n2-standard-4  - 4 vCPU, 16 GB RAM — CPU only
}

variable "gpu_type" {
  description = "GPU accelerator type (empty string = no GPU)"
  type        = string
  default     = "nvidia-tesla-t4"

  # Options:
  # nvidia-tesla-t4       - T4 GPU, 16 GB VRAM
  # nvidia-l4             - L4 GPU, 24 GB VRAM (use g2 machine types)
  # nvidia-tesla-v100     - V100 GPU, 16 GB VRAM
  # nvidia-a100-80gb      - A100 GPU, 80 GB VRAM (use a2-ultragpu machine types)
  # ""                    - No GPU (CPU-only)
}

variable "gpu_count" {
  description = "Number of GPUs to attach (0 = no GPU)"
  type        = number
  default     = 1

  validation {
    condition     = contains([0, 1, 2, 4, 8], var.gpu_count)
    error_message = "gpu_count must be 0, 1, 2, 4, or 8."
  }
}

variable "boot_disk_image" {
  description = "Boot disk image (Deep Learning VM image recommended)"
  type        = string
  default     = "projects/deeplearning-platform-release/global/images/family/common-cu118"

  # Options:
  # projects/deeplearning-platform-release/global/images/family/common-cu118
  # projects/deeplearning-platform-release/global/images/family/common-cpu
  # projects/ubuntu-os-cloud/global/images/family/ubuntu-2204-lts
}

variable "boot_disk_size_gb" {
  description = "Boot disk size in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.boot_disk_size_gb >= 50 && var.boot_disk_size_gb <= 2000
    error_message = "boot_disk_size_gb must be between 50 and 2000 GB."
  }
}

variable "data_disk_size_gb" {
  description = "Data disk size in GB (for models and datasets)"
  type        = number
  default     = 500

  validation {
    condition     = var.data_disk_size_gb >= 50 && var.data_disk_size_gb <= 65536
    error_message = "data_disk_size_gb must be between 50 and 65536 GB."
  }
}

variable "use_spot_vm" {
  description = "Use Spot VM for cost savings (VM may be preempted with 30-second notice)"
  type        = bool
  default     = false
}

# --- Access Variables ---

variable "developer_emails" {
  description = "List of developer email addresses to grant IAP SSH access"
  type        = list(string)
  default     = []

  # Example: ["alice@company.com", "bob@company.com"]
}
