output "resource_group_name" {
  description = "Name of the resource group containing all sandbox resources"
  value       = azurerm_resource_group.sandbox.name
}

output "vm_id" {
  description = "Resource ID of the sandbox virtual machine"
  value       = azurerm_linux_virtual_machine.sandbox.id
}

output "vm_name" {
  description = "Name of the sandbox virtual machine"
  value       = azurerm_linux_virtual_machine.sandbox.name
}

output "vm_private_ip" {
  description = "Private IP address of the sandbox VM (no public IP assigned)"
  value       = azurerm_network_interface.sandbox.private_ip_address
}

output "vm_size" {
  description = "Size of the VM (e.g., Standard_NC4as_T4_v3)"
  value       = azurerm_linux_virtual_machine.sandbox.size
}

output "vm_managed_identity_principal_id" {
  description = "Principal ID of the system-assigned managed identity"
  value       = azurerm_linux_virtual_machine.sandbox.identity[0].principal_id
}

output "key_vault_name" {
  description = "Name of the Azure Key Vault for secrets management"
  value       = azurerm_key_vault.sandbox.name
}

output "key_vault_uri" {
  description = "URI of the Azure Key Vault"
  value       = azurerm_key_vault.sandbox.vault_uri
}

output "storage_account_name" {
  description = "Name of the storage account for models and datasets"
  value       = azurerm_storage_account.sandbox.name
}

output "storage_account_primary_endpoint" {
  description = "Primary blob endpoint of the storage account"
  value       = azurerm_storage_account.sandbox.primary_blob_endpoint
}

output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = azurerm_virtual_network.sandbox.id
}

output "subnet_id" {
  description = "Resource ID of the sandbox subnet"
  value       = azurerm_subnet.sandbox.id
}

output "nsg_id" {
  description = "Resource ID of the network security group"
  value       = azurerm_network_security_group.sandbox.id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace (if monitoring enabled)"
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.sandbox[0].id : null
}

output "log_analytics_workspace_key" {
  description = "Primary shared key of the Log Analytics workspace"
  sensitive   = true
  value       = var.enable_monitoring ? azurerm_log_analytics_workspace.sandbox[0].primary_shared_key : null
}

output "connection_instructions" {
  description = "Instructions for connecting to the sandbox"
  value       = <<-EOT
    Sandbox VM provisioned successfully!

    VM Name:       ${azurerm_linux_virtual_machine.sandbox.name}
    Private IP:    ${azurerm_network_interface.sandbox.private_ip_address}
    VM Size:       ${azurerm_linux_virtual_machine.sandbox.size}

    To connect (requires VPN/Bastion or JIT access):
      ssh -i ~/.ssh/sandbox_key ${var.admin_username}@${azurerm_network_interface.sandbox.private_ip_address}

    To enable JIT access:
      az security jit-policy initiate \
        --resource-group ${azurerm_resource_group.sandbox.name} \
        --name default \
        --virtual-machines '[{"id": "${azurerm_linux_virtual_machine.sandbox.id}", "ports": [{"number": 22, "duration": "PT4H", "allowedSourceAddressPrefix": "YOUR_IP"}]}]'

    Key Vault URI: ${azurerm_key_vault.sandbox.vault_uri}
    Storage:       ${azurerm_storage_account.sandbox.primary_blob_endpoint}
    Auto-shutdown: ${var.auto_shutdown_time} UTC daily
  EOT
}
