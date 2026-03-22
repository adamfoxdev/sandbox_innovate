# Azure VM Sandbox Setup Guide

Step-by-step instructions for provisioning a secure Azure VM AI sandbox, covering prerequisites, CLI setup, Terraform IaC, network configuration, hardening, and validation.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [CLI Setup (Azure Portal Alternative)](#cli-setup)
- [Terraform IaC Setup (Recommended)](#terraform-iac-setup-recommended)
- [Network and Identity Configuration](#network-and-identity-configuration)
- [Hardening Steps](#hardening-steps)
- [Validation Tests](#validation-tests)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before starting, ensure you have:

1. **Azure CLI** installed and authenticated:

   ```bash
   # Install Azure CLI
   curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

   # Authenticate
   az login

   # Verify
   az account show
   az account set --subscription "Your Subscription Name"
   ```

2. **Terraform** >= 1.5.0:

   ```bash
   # Install via tfenv (recommended)
   git clone https://github.com/tfutils/tfenv.git ~/.tfenv
   echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc
   source ~/.bashrc
   tfenv install 1.7.0
   tfenv use 1.7.0
   terraform version
   ```

3. **Required permissions** in Azure:
   - Contributor role on the target subscription or resource group
   - User Access Administrator (to assign managed identity roles)
   - Key Vault Administrator (to create Key Vault and manage secrets)

4. **Quota check** — verify GPU quota in your target region:

   ```bash
   # Check NC-series vCPU quota
   az vm list-usage --location eastus \
     --query "[?contains(name.value, 'NCSv3')] | [*].{Name:name.localizedValue, Used:currentValue, Limit:limit}" \
     -o table
   ```

   If quota is 0, request via Azure Portal: Subscriptions → Usage + quotas → Request increase.

---

## CLI Setup

### Step 1: Create Resource Group

```bash
LOCATION="eastus"
RG_NAME="rg-ai-sandbox"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

az group create \
  --name $RG_NAME \
  --location $LOCATION \
  --tags Environment=sandbox Project=ai-sandbox Team=yourteam
```

### Step 2: Create Virtual Network and Subnet

```bash
VNET_NAME="vnet-ai-sandbox"
SUBNET_NAME="snet-sandbox"

az network vnet create \
  --resource-group $RG_NAME \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $SUBNET_NAME \
  --subnet-prefix 10.0.1.0/24

# Disable private endpoint network policies (required for private endpoints)
az network vnet subnet update \
  --resource-group $RG_NAME \
  --vnet-name $VNET_NAME \
  --name $SUBNET_NAME \
  --disable-private-endpoint-network-policies true
```

### Step 3: Create Network Security Group

```bash
NSG_NAME="nsg-ai-sandbox"

az network nsg create \
  --resource-group $RG_NAME \
  --name $NSG_NAME

# Allow SSH from Azure Bastion subnet (adjust if using Bastion)
az network nsg rule create \
  --resource-group $RG_NAME \
  --nsg-name $NSG_NAME \
  --name AllowSSHFromBastion \
  --priority 100 \
  --protocol Tcp \
  --destination-port-ranges 22 \
  --source-address-prefixes 10.0.255.0/27 \
  --access Allow

# Deny all other inbound
az network nsg rule create \
  --resource-group $RG_NAME \
  --nsg-name $NSG_NAME \
  --name DenyAllInbound \
  --priority 4096 \
  --protocol '*' \
  --destination-port-ranges '*' \
  --source-address-prefixes '*' \
  --access Deny \
  --direction Inbound

# Associate NSG with subnet
az network vnet subnet update \
  --resource-group $RG_NAME \
  --vnet-name $VNET_NAME \
  --name $SUBNET_NAME \
  --network-security-group $NSG_NAME
```

### Step 4: Create Key Vault

```bash
KV_NAME="kv-ai-sandbox-$(openssl rand -hex 4)"

az keyvault create \
  --name $KV_NAME \
  --resource-group $RG_NAME \
  --location $LOCATION \
  --sku standard \
  --enable-rbac-authorization true \
  --default-action Deny \
  --bypass AzureServices

echo "Key Vault name: $KV_NAME"
```

### Step 5: Create the VM

```bash
VM_NAME="vm-ai-sandbox"
ADMIN_USER="sandboxadmin"
VM_SIZE="Standard_NC4as_T4_v3"

# Create SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/sandbox_key -C "sandbox-key" -N ""

az vm create \
  --resource-group $RG_NAME \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --size $VM_SIZE \
  --admin-username $ADMIN_USER \
  --ssh-key-values ~/.ssh/sandbox_key.pub \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --nsg $NSG_NAME \
  --public-ip-address "" \
  --os-disk-size-gb 128 \
  --storage-sku Premium_LRS \
  --assign-identity \
  --tags Environment=sandbox

# Get the managed identity principal ID
PRINCIPAL_ID=$(az vm identity show \
  --name $VM_NAME \
  --resource-group $RG_NAME \
  --query principalId -o tsv)
```

### Step 6: Assign Permissions to Managed Identity

```bash
# Grant Key Vault Secrets User role
KV_ID=$(az keyvault show --name $KV_NAME --resource-group $RG_NAME --query id -o tsv)
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Key Vault Secrets User" \
  --scope $KV_ID

# Grant Contributor on the resource group (for monitoring writes)
az role assignment create \
  --assignee $PRINCIPAL_ID \
  --role "Monitoring Metrics Publisher" \
  --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG_NAME
```

### Step 7: Configure Auto-Shutdown

```bash
az vm auto-shutdown \
  --resource-group $RG_NAME \
  --name $VM_NAME \
  --time 2000 \
  --email "team@company.com"
```

---

## Terraform IaC Setup (Recommended)

For repeatable, version-controlled deployments, use the provided Terraform templates:

```bash
cd templates/azure-vm

# Copy and customize variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# subscription_id = "your-subscription-id"
# location        = "eastus"
# team_name       = "yourteam"
# admin_public_key = file("~/.ssh/sandbox_key.pub")

# Initialize Terraform
terraform init

# Preview changes
terraform plan -out=tfplan

# Apply
terraform apply tfplan

# Get outputs
terraform output vm_private_ip
terraform output key_vault_name
```

---

## Network and Identity Configuration

### Enable Private Endpoints for Key Vault and Storage

```bash
# Create private endpoint for Key Vault
az network private-endpoint create \
  --name pe-keyvault \
  --resource-group $RG_NAME \
  --vnet-name $VNET_NAME \
  --subnet $SUBNET_NAME \
  --private-connection-resource-id $KV_ID \
  --group-id vault \
  --connection-name conn-keyvault

# Create private DNS zone for Key Vault
az network private-dns zone create \
  --resource-group $RG_NAME \
  --name "privatelink.vaultcore.azure.net"

az network private-dns link vnet create \
  --resource-group $RG_NAME \
  --zone-name "privatelink.vaultcore.azure.net" \
  --name link-sandbox-kv \
  --virtual-network $VNET_NAME \
  --registration-enabled false
```

### Enable Entra ID SSH Login

```bash
az vm extension set \
  --publisher Microsoft.Azure.ActiveDirectory \
  --name AADSSHLoginForLinux \
  --resource-group $RG_NAME \
  --vm-name $VM_NAME

# Grant VM User Login to developer group
az role assignment create \
  --assignee "developer@company.com" \
  --role "Virtual Machine User Login" \
  --scope $(az vm show --name $VM_NAME --resource-group $RG_NAME --query id -o tsv)
```

---

## Hardening Steps

### 1. Install NVIDIA Drivers (for GPU VMs)

```bash
# SSH into the VM (via Bastion or JIT access)
az ssh vm --name $VM_NAME --resource-group $RG_NAME

# On the VM:
sudo apt update
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers install

# Verify
nvidia-smi
```

### 2. Install NVIDIA Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 3. OS Security Hardening

```bash
# Enable automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Configure firewall (UFW)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.0.0.0/8 to any port 22 proto tcp
sudo ufw enable

# Disable password authentication in SSH
sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Install and configure fail2ban
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# Audit logging
sudo apt install -y auditd
sudo systemctl enable --now auditd
```

### 4. Install Azure Monitor Agent

```bash
# On the VM
curl -L -O https://raw.githubusercontent.com/microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh
sudo sh onboard_agent.sh -w <WORKSPACE_ID> -s <WORKSPACE_KEY> -d opinsights.azure.com
```

---

## Validation Tests

Run these tests after provisioning to confirm everything is working:

```bash
# 1. Verify no public IP
PUBLIC_IP=$(az vm show --name $VM_NAME --resource-group $RG_NAME \
  --show-details --query publicIps -o tsv)
[ -z "$PUBLIC_IP" ] && echo "✅ No public IP" || echo "❌ Public IP found: $PUBLIC_IP"

# 2. Verify NSG is attached
NSG=$(az network nic show \
  --ids $(az vm show --name $VM_NAME --resource-group $RG_NAME --query 'networkProfile.networkInterfaces[0].id' -o tsv) \
  --query 'networkSecurityGroup.id' -o tsv)
[ -n "$NSG" ] && echo "✅ NSG attached" || echo "❌ No NSG"

# 3. Verify managed identity is assigned
IDENTITY=$(az vm identity show --name $VM_NAME --resource-group $RG_NAME \
  --query 'type' -o tsv 2>/dev/null)
[ "$IDENTITY" = "SystemAssigned" ] && echo "✅ Managed identity assigned" || echo "❌ No managed identity"

# 4. Verify auto-shutdown
SHUTDOWN=$(az vm auto-shutdown show --name $VM_NAME --resource-group $RG_NAME \
  --query 'status' -o tsv 2>/dev/null)
[ "$SHUTDOWN" = "Enabled" ] && echo "✅ Auto-shutdown enabled" || echo "❌ Auto-shutdown not configured"

# 5. From the VM — verify GPU (for NC series)
# az ssh vm --name $VM_NAME --resource-group $RG_NAME -- nvidia-smi
# ✅ Should show NVIDIA T4 or V100 etc.

# 6. Verify Key Vault access from VM (using managed identity)
# az ssh vm --name $VM_NAME --resource-group $RG_NAME -- \
#   az keyvault secret list --vault-name $KV_NAME
# ✅ Should return empty list or secrets list
```

---

## Troubleshooting

### Issue: Cannot connect to VM via SSH

**Symptoms**: Connection timeout or refused

**Solutions**:
1. Verify JIT access is enabled and you've requested access
2. Check NSG rules: `az network nsg rule list --resource-group $RG_NAME --nsg-name $NSG_NAME -o table`
3. If using Bastion, ensure Bastion subnet exists: `10.0.255.0/27`
4. Try Azure Serial Console for emergency access: Portal → VM → Serial console

### Issue: GPU not recognized (`nvidia-smi` fails)

**Symptoms**: `nvidia-smi: command not found` or driver error

**Solutions**:
1. Verify VM is NC/NV/ND series: `az vm show --name $VM_NAME --resource-group $RG_NAME --query hardwareProfile.vmSize -o tsv`
2. Reinstall drivers: `sudo ubuntu-drivers install --gpgpu`
3. Reboot: `sudo reboot`
4. Check driver version compatibility with CUDA requirements

### Issue: Key Vault access denied

**Symptoms**: `403 Forbidden` when accessing Key Vault from VM

**Solutions**:
1. Check managed identity is assigned: `az vm identity show ...`
2. Verify role assignment: `az role assignment list --assignee $PRINCIPAL_ID -o table`
3. Check Key Vault network rules: `az keyvault show --name $KV_NAME --query 'properties.networkAcls'`
4. Ensure private endpoint DNS is configured correctly

### Issue: Terraform state issues

**Symptoms**: Inconsistent state between Terraform and Azure

**Solutions**:
```bash
# Refresh state
terraform refresh

# Import existing resource
terraform import azurerm_resource_group.main /subscriptions/XXX/resourceGroups/rg-ai-sandbox

# If state is corrupted, remove specific resource from state
terraform state rm azurerm_virtual_machine.sandbox
```

### Issue: GPU quota insufficient

**Symptoms**: `QuotaExceeded` error when creating VM

**Solutions**:
1. Check current quota: `az vm list-usage --location eastus -o table | grep -i nc`
2. Request increase: Azure Portal → Subscriptions → Usage + Quotas → Request Increase
3. Try alternative region with available quota: `eastus2`, `westus2`, `westeurope`
4. Try smaller VM size: `Standard_NC4as_T4_v3` (uses fewer vCPUs)
