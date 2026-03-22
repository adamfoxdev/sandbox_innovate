variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "eastus"

  validation {
    condition     = contains(["eastus", "eastus2", "westus", "westus2", "westus3", "northeurope", "westeurope", "uksouth", "ukwest", "southeastasia", "australiaeast"], var.location)
    error_message = "Location must be a valid Azure region."
  }
}

variable "project_name" {
  description = "Short name for the project (used in resource naming)"
  type        = string
  default     = "aisandbox"

  validation {
    condition     = length(var.project_name) <= 12 && can(regex("^[a-z0-9]+$", var.project_name))
    error_message = "project_name must be 1-12 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Environment name (sandbox, dev, staging)"
  type        = string
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "dev", "staging"], var.environment)
    error_message = "environment must be one of: sandbox, dev, staging."
  }
}

variable "team_name" {
  description = "Team name for tagging resources"
  type        = string
  default     = "ai-team"
}

# --- Network Variables ---

variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_address_prefix" {
  description = "Address prefix for the sandbox subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr_ranges" {
  description = "CIDR ranges allowed to access the sandbox (VPN, corporate network, bastion)"
  type        = list(string)
  default     = ["10.0.0.0/8"]  # Override with your corporate VPN/Bastion range

  validation {
    condition     = length(var.allowed_cidr_ranges) > 0
    error_message = "At least one allowed CIDR range must be specified."
  }
}

# --- VM Variables ---

variable "vm_size" {
  description = "Azure VM size for the sandbox. GPU-enabled sizes recommended for AI workloads."
  type        = string
  default     = "Standard_NC4as_T4_v3"

  # Common options:
  # Standard_NC4as_T4_v3  - 1x T4 GPU, 4 vCPU, 28 GB RAM (~$0.526/hr)
  # Standard_NC8as_T4_v3  - 1x T4 GPU, 8 vCPU, 56 GB RAM (~$0.752/hr)
  # Standard_NC6s_v3      - 1x V100 GPU, 6 vCPU, 112 GB RAM (~$1.14/hr)
  # Standard_NV36ads_A10_v5 - 1x A10 GPU, 36 vCPU, 440 GB RAM (~$2.28/hr)
  # Standard_D4s_v5       - CPU only, 4 vCPU, 16 GB RAM (~$0.192/hr)
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
  default     = "sandboxadmin"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,31}$", var.admin_username))
    error_message = "admin_username must start with a lowercase letter and be 3-32 characters."
  }
}

variable "admin_ssh_public_key" {
  description = "SSH public key for VM access. Generate with: ssh-keygen -t ed25519 -f ~/.ssh/sandbox_key"
  type        = string
  sensitive   = true
}

variable "os_disk_size_gb" {
  description = "Size of the OS disk in GB"
  type        = number
  default     = 128

  validation {
    condition     = var.os_disk_size_gb >= 30 && var.os_disk_size_gb <= 1024
    error_message = "os_disk_size_gb must be between 30 and 1024 GB."
  }
}

variable "data_disk_size_gb" {
  description = "Size of the data disk in GB (for models and datasets)"
  type        = number
  default     = 256

  validation {
    condition     = var.data_disk_size_gb >= 32 && var.data_disk_size_gb <= 32767
    error_message = "data_disk_size_gb must be between 32 and 32767 GB."
  }
}

# --- Auto-Shutdown Variables ---

variable "auto_shutdown_time" {
  description = "Daily auto-shutdown time in UTC (HHMM format)"
  type        = string
  default     = "2000"

  validation {
    condition     = can(regex("^[0-2][0-9][0-5][0-9]$", var.auto_shutdown_time))
    error_message = "auto_shutdown_time must be in HHMM format (e.g., 2000 for 8:00 PM)."
  }
}

variable "auto_shutdown_timezone" {
  description = "Timezone for auto-shutdown schedule"
  type        = string
  default     = "UTC"
}

variable "shutdown_notification_email" {
  description = "Email address for shutdown notifications (empty to disable)"
  type        = string
  default     = ""
}

# --- Monitoring Variables ---

variable "enable_monitoring" {
  description = "Enable Azure Monitor and Log Analytics workspace"
  type        = bool
  default     = true
}

variable "enable_entra_id_ssh" {
  description = "Enable Entra ID (Azure AD) SSH authentication"
  type        = bool
  default     = false  # Set to true if your subscription supports it
}
