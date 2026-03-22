terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.90"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}

# --- Data Sources ---

data "azurerm_client_config" "current" {}

# --- Random suffix for globally unique names ---

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

# --- Resource Group ---

resource "azurerm_resource_group" "sandbox" {
  name     = "rg-${var.project_name}-${var.environment}"
  location = var.location

  tags = local.common_tags
}

# --- Virtual Network ---

resource "azurerm_virtual_network" "sandbox" {
  name                = "vnet-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location
  address_space       = [var.vnet_address_space]

  tags = local.common_tags
}

resource "azurerm_subnet" "sandbox" {
  name                 = "snet-sandbox"
  resource_group_name  = azurerm_resource_group.sandbox.name
  virtual_network_name = azurerm_virtual_network.sandbox.name
  address_prefixes     = [var.subnet_address_prefix]

  private_endpoint_network_policies = "Disabled"
}

# --- Network Security Group ---

resource "azurerm_network_security_group" "sandbox" {
  name                = "nsg-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location

  # Allow JupyterLab from approved CIDR ranges
  security_rule {
    name                       = "AllowJupyterFromApprovedRanges"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8888"
    source_address_prefixes    = var.allowed_cidr_ranges
    destination_address_prefix = "*"
  }

  # Allow SSH from approved CIDR ranges (for direct access)
  security_rule {
    name                       = "AllowSSHFromApprovedRanges"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefixes    = var.allowed_cidr_ranges
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic
  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "sandbox" {
  subnet_id                 = azurerm_subnet.sandbox.id
  network_security_group_id = azurerm_network_security_group.sandbox.id
}

# --- Network Interface (No Public IP) ---

resource "azurerm_network_interface" "sandbox" {
  name                = "nic-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.sandbox.id
    private_ip_address_allocation = "Dynamic"
    # No public IP attached
  }

  tags = local.common_tags
}

# --- Key Vault ---

resource "azurerm_key_vault" "sandbox" {
  name                        = "kv-${var.project_name}-${random_string.suffix.result}"
  resource_group_name         = azurerm_resource_group.sandbox.name
  location                    = azurerm_resource_group.sandbox.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  enable_rbac_authorization   = true
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    virtual_network_subnet_ids = [azurerm_subnet.sandbox.id]
  }

  tags = local.common_tags
}

# --- Storage Account for Models and Datasets ---

resource "azurerm_storage_account" "sandbox" {
  name                            = "sa${var.project_name}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.sandbox.name
  location                        = azurerm_resource_group.sandbox.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    virtual_network_subnet_ids = [azurerm_subnet.sandbox.id]
  }

  tags = local.common_tags
}

resource "azurerm_storage_container" "models" {
  name                  = "models"
  storage_account_name  = azurerm_storage_account.sandbox.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "datasets" {
  name                  = "datasets"
  storage_account_name  = azurerm_storage_account.sandbox.name
  container_access_type = "private"
}

resource "azurerm_storage_container" "notebooks" {
  name                  = "notebooks"
  storage_account_name  = azurerm_storage_account.sandbox.name
  container_access_type = "private"
}

# --- Linux Virtual Machine ---

resource "azurerm_linux_virtual_machine" "sandbox" {
  name                  = "vm-${var.project_name}-${var.environment}"
  resource_group_name   = azurerm_resource_group.sandbox.name
  location              = azurerm_resource_group.sandbox.location
  size                  = var.vm_size
  admin_username        = var.admin_username
  network_interface_ids = [azurerm_network_interface.sandbox.id]

  # Use SSH key authentication (no password)
  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  # Disable password authentication
  disable_password_authentication = true

  # System-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "osdisk-${var.project_name}-${var.environment}"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
    disk_encryption_set_id = null  # Uses platform-managed key; use CMK in production
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Enable boot diagnostics
  boot_diagnostics {}

  custom_data = base64encode(templatefile("${path.module}/cloud-init.yaml.tpl", {
    admin_username = var.admin_username
  }))

  tags = local.common_tags
}

# --- Data Disk for Models and Datasets ---

resource "azurerm_managed_disk" "data" {
  name                 = "disk-data-${var.project_name}-${var.environment}"
  resource_group_name  = azurerm_resource_group.sandbox.name
  location             = azurerm_resource_group.sandbox.location
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb

  tags = local.common_tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.sandbox.id
  lun                = 0
  caching            = "ReadWrite"
}

# --- Role Assignments for Managed Identity ---

# Key Vault Secrets User — read secrets
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = azurerm_key_vault.sandbox.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_virtual_machine.sandbox.identity[0].principal_id
}

# Storage Blob Data Contributor — read/write to sandbox storage
resource "azurerm_role_assignment" "storage_contributor" {
  scope                = azurerm_storage_account.sandbox.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.sandbox.identity[0].principal_id
}

# Monitoring Metrics Publisher — write metrics
resource "azurerm_role_assignment" "monitoring_publisher" {
  scope                = azurerm_resource_group.sandbox.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_linux_virtual_machine.sandbox.identity[0].principal_id
}

# --- Auto-Shutdown Schedule ---

resource "azurerm_dev_test_global_vm_shutdown_schedule" "sandbox" {
  virtual_machine_id = azurerm_linux_virtual_machine.sandbox.id
  location           = azurerm_resource_group.sandbox.location
  enabled            = true

  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone

  notification_settings {
    enabled         = var.shutdown_notification_email != ""
    time_in_minutes = 30
    email           = var.shutdown_notification_email
  }
}

# --- Log Analytics Workspace ---

resource "azurerm_log_analytics_workspace" "sandbox" {
  count               = var.enable_monitoring ? 1 : 0
  name                = "law-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.sandbox.name
  location            = azurerm_resource_group.sandbox.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.common_tags
}

# --- VM Extension: Azure Monitor Agent ---

resource "azurerm_virtual_machine_extension" "monitor_agent" {
  count                      = var.enable_monitoring ? 1 : 0
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.sandbox.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  tags = local.common_tags
}

# --- VM Extension: Entra ID SSH Login ---

resource "azurerm_virtual_machine_extension" "aad_ssh" {
  count                = var.enable_entra_id_ssh ? 1 : 0
  name                 = "AADSSHLoginForLinux"
  virtual_machine_id   = azurerm_linux_virtual_machine.sandbox.id
  publisher            = "Microsoft.Azure.ActiveDirectory"
  type                 = "AADSSHLoginForLinux"
  type_handler_version = "1.0"

  tags = local.common_tags
}

# --- Local Values ---

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    Team        = var.team_name
    ManagedBy   = "terraform"
    CreatedDate = formatdate("YYYY-MM-DD", timestamp())
  }
}
