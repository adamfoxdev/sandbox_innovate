variable "region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name for the project (used in resource naming, max 12 chars)"
  type        = string
  default     = "aisandbox"

  validation {
    condition     = length(var.project_name) <= 12 && can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with hyphens, max 12 chars."
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
  description = "Team name for resource tagging"
  type        = string
  default     = "ai-team"
}

# --- Network Variables ---

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private sandbox subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr_ranges" {
  description = "CIDR ranges allowed to access the sandbox (corporate VPN, bastion)"
  type        = list(string)
  default     = ["10.0.0.0/8"]

  validation {
    condition     = length(var.allowed_cidr_ranges) > 0
    error_message = "At least one allowed CIDR range must be specified."
  }
}

# --- EC2 Instance Variables ---

variable "instance_type" {
  description = "EC2 instance type. GPU instances recommended for AI workloads."
  type        = string
  default     = "g4dn.xlarge"

  # Common options:
  # g4dn.xlarge   - 1x T4 GPU, 4 vCPU, 16 GB RAM (~$0.526/hr)
  # g4dn.2xlarge  - 1x T4 GPU, 8 vCPU, 32 GB RAM (~$0.752/hr)
  # g5.xlarge     - 1x A10G GPU, 4 vCPU, 16 GB RAM (~$1.006/hr)
  # g5.2xlarge    - 1x A10G GPU, 8 vCPU, 32 GB RAM (~$1.212/hr)
  # p3.2xlarge    - 1x V100 GPU, 8 vCPU, 61 GB RAM (~$3.06/hr)
  # c5.2xlarge    - CPU only, 8 vCPU, 16 GB RAM (~$0.34/hr)
}

variable "root_volume_size_gb" {
  description = "Size of root EBS volume in GB"
  type        = number
  default     = 100

  validation {
    condition     = var.root_volume_size_gb >= 30 && var.root_volume_size_gb <= 1000
    error_message = "root_volume_size_gb must be between 30 and 1000 GB."
  }
}

variable "data_volume_size_gb" {
  description = "Size of data EBS volume in GB (for models and datasets)"
  type        = number
  default     = 500

  validation {
    condition     = var.data_volume_size_gb >= 50 && var.data_volume_size_gb <= 16384
    error_message = "data_volume_size_gb must be between 50 and 16384 GB."
  }
}

variable "use_spot_instance" {
  description = "Use Spot Instance for cost savings (instance may be interrupted)"
  type        = bool
  default     = false
}

variable "spot_max_price" {
  description = "Maximum Spot price per hour (empty string = on-demand price cap)"
  type        = string
  default     = ""
}

# --- Auto-Shutdown Variables ---

variable "enable_auto_shutdown" {
  description = "Enable automatic shutdown when instance is idle"
  type        = bool
  default     = true
}

variable "idle_shutdown_minutes" {
  description = "Minutes of CPU idle time before auto-shutdown triggers"
  type        = number
  default     = 30

  validation {
    condition     = var.idle_shutdown_minutes >= 10 && var.idle_shutdown_minutes <= 120
    error_message = "idle_shutdown_minutes must be between 10 and 120."
  }
}
