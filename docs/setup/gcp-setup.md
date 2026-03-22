# GCP Compute Engine Sandbox Setup Guide

Step-by-step instructions for provisioning a secure GCP Compute Engine AI sandbox using gcloud CLI and Terraform.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [gcloud CLI Setup](#gcloud-cli-setup)
- [Terraform IaC Setup (Recommended)](#terraform-iac-setup-recommended)
- [Network and Identity Configuration](#network-and-identity-configuration)
- [Hardening Steps](#hardening-steps)
- [Validation Tests](#validation-tests)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

1. **gcloud CLI** installed and authenticated:

   ```bash
   # Install gcloud CLI
   curl https://sdk.cloud.google.com | bash
   exec -l $SHELL

   # Initialize and authenticate
   gcloud init
   gcloud auth application-default login

   # Verify
   gcloud config list
   gcloud auth list
   ```

2. **Required APIs enabled**:

   ```bash
   PROJECT_ID="prj-ai-sandbox"

   gcloud services enable \
     compute.googleapis.com \
     iam.googleapis.com \
     secretmanager.googleapis.com \
     artifactregistry.googleapis.com \
     storage.googleapis.com \
     logging.googleapis.com \
     monitoring.googleapis.com \
     iap.googleapis.com \
     cloudresourcemanager.googleapis.com \
     --project $PROJECT_ID
   ```

3. **GPU quota check**:

   ```bash
   # Check NVIDIA T4 GPU quota in us-central1
   gcloud compute regions describe us-central1 \
     --project $PROJECT_ID \
     --format="table(quotas.metric,quotas.limit,quotas.usage)" | grep -i "gpu\|nvidia"
   ```

   If quota is 0, request via Console: IAM & Admin → Quotas → Filter by "GPU" → Edit Quota.

4. **Terraform** >= 1.5.0 (see other setup guides for installation).

---

## gcloud CLI Setup

### Step 1: Set Environment Variables

```bash
PROJECT_ID="prj-ai-sandbox"
REGION="us-central1"
ZONE="${REGION}-a"
TEAM_NAME="yourteam"

gcloud config set project $PROJECT_ID
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE
```

### Step 2: Create VPC Network

```bash
# Create custom mode VPC (no auto-subnets)
gcloud compute networks create vpc-ai-sandbox \
  --subnet-mode custom \
  --bgp-routing-mode regional

# Create subnet with Private Google Access enabled
gcloud compute networks subnets create subnet-sandbox \
  --network vpc-ai-sandbox \
  --region $REGION \
  --range 10.0.1.0/24 \
  --enable-private-ip-google-access \
  --enable-flow-logs \
  --logging-aggregation-interval interval-5-sec \
  --logging-flow-sampling 0.5
```

### Step 3: Configure Firewall Rules

```bash
# Allow IAP SSH (Identity-Aware Proxy tunneling)
gcloud compute firewall-rules create allow-iap-ssh \
  --network vpc-ai-sandbox \
  --allow tcp:22 \
  --source-ranges 35.235.240.0/20 \
  --target-tags ai-sandbox \
  --description "Allow SSH via Identity-Aware Proxy"

# Allow internal VPC communication
gcloud compute firewall-rules create allow-internal \
  --network vpc-ai-sandbox \
  --allow tcp,udp,icmp \
  --source-ranges 10.0.0.0/8 \
  --target-tags ai-sandbox

# Allow JupyterLab from VPN (adjust source range)
gcloud compute firewall-rules create allow-jupyterlab \
  --network vpc-ai-sandbox \
  --allow tcp:8888 \
  --source-ranges 192.168.0.0/16 \
  --target-tags ai-sandbox \
  --description "JupyterLab access from corporate VPN"

# Deny all other ingress explicitly
gcloud compute firewall-rules create deny-all-ingress \
  --network vpc-ai-sandbox \
  --action DENY \
  --direction INGRESS \
  --rules all \
  --priority 65534 \
  --target-tags ai-sandbox
```

### Step 4: Create Cloud Router and NAT (Optional)

For controlled internet egress (model downloads):

```bash
gcloud compute routers create router-sandbox \
  --network vpc-ai-sandbox \
  --region $REGION

gcloud compute routers nats create nat-sandbox \
  --router router-sandbox \
  --region $REGION \
  --nat-all-subnet-ip-ranges \
  --auto-allocate-nat-external-ips

# For air-gapped: skip Cloud NAT — pre-stage dependencies in Artifact Registry
```

### Step 5: Create Service Account

```bash
SA_NAME="sa-ai-sandbox"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud iam service-accounts create $SA_NAME \
  --display-name "AI Sandbox Service Account" \
  --description "Service account for AI sandbox VM instances"

# Grant minimal IAM roles
# Cloud Storage access (limited to sandbox bucket)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/storage.objectUser" \
  --condition="expression=resource.name.startsWith('projects/_/buckets/sandbox-'),title=sandbox-buckets-only"

# Secret Manager access (limited to sandbox/* secrets)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor" \
  --condition="expression=resource.name.startsWith('projects/${PROJECT_ID}/secrets/sandbox-'),title=sandbox-secrets-only"

# Logging and monitoring
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/logging.logWriter"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/monitoring.metricWriter"

# Artifact Registry read
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/artifactregistry.reader"
```

### Step 6: Create Cloud Storage Bucket

```bash
BUCKET_NAME="sandbox-models-${PROJECT_ID}"

# Create bucket
gcloud storage buckets create gs://$BUCKET_NAME \
  --location $REGION \
  --uniform-bucket-level-access \
  --public-access-prevention

# Enable CMEK (requires Cloud KMS key — optional but recommended)
# gcloud storage buckets update gs://$BUCKET_NAME \
#   --default-kms-key projects/$PROJECT_ID/locations/$REGION/keyRings/sandbox-keyring/cryptoKeys/sandbox-key

# Set lifecycle policy
cat > /tmp/lifecycle.json << 'EOF'
{
  "rule": [
    {
      "action": {"type": "SetStorageClass", "storageClass": "NEARLINE"},
      "condition": {"age": 30, "matchesStorageClass": ["STANDARD"]}
    },
    {
      "action": {"type": "Delete"},
      "condition": {"age": 365}
    }
  ]
}
EOF
gcloud storage buckets update gs://$BUCKET_NAME --lifecycle-file=/tmp/lifecycle.json
```

### Step 7: Create the Compute Instance

```bash
VM_NAME="vm-ai-sandbox"

gcloud compute instances create $VM_NAME \
  --machine-type n1-standard-4 \
  --accelerator type=nvidia-tesla-t4,count=1 \
  --maintenance-policy TERMINATE \
  --restart-on-failure \
  --image-family common-cu118 \
  --image-project deeplearning-platform-release \
  --boot-disk-size 100GB \
  --boot-disk-type pd-ssd \
  --boot-disk-device-name sandbox-os \
  --create-disk name=sandbox-data,size=500GB,type=pd-ssd,auto-delete=no \
  --subnet subnet-sandbox \
  --no-address \
  --service-account $SA_EMAIL \
  --scopes cloud-platform \
  --tags ai-sandbox \
  --labels environment=sandbox,team=$TEAM_NAME \
  --metadata \
    enable-oslogin=TRUE,\
    enable-oslogin-2fa=FALSE,\
    startup-script='#!/bin/bash
      # Install NVIDIA drivers (usually pre-installed on DL images)
      nvidia-smi || (apt-get update && apt-get install -y nvidia-driver-525 && reboot)
      # Mount data disk
      if ! blkid /dev/sdb; then
        mkfs.ext4 /dev/sdb
      fi
      mkdir -p /data
      mount /dev/sdb /data
      echo "/dev/sdb /data ext4 defaults 0 2" >> /etc/fstab
    '

echo "VM created: $VM_NAME"
```

---

## Terraform IaC Setup (Recommended)

```bash
cd templates/gcp-compute

# Configure application default credentials
gcloud auth application-default login

# Set variables
cat > terraform.tfvars << EOF
project_id   = "prj-ai-sandbox"
region       = "us-central1"
zone         = "us-central1-a"
machine_type = "n1-standard-4"
gpu_type     = "nvidia-tesla-t4"
gpu_count    = 1
team_name    = "yourteam"
EOF

# Initialize and apply
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# Get outputs
terraform output vm_name
terraform output bucket_name
terraform output service_account_email
```

---

## Network and Identity Configuration

### Grant IAP Access to Developers

```bash
# Grant IAP Tunnel User role to developer group
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="group:sandbox-developers@company.com" \
  --role="roles/iap.tunnelResourceAccessor"

# Grant OS Login access (to SSH into instances)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="group:sandbox-developers@company.com" \
  --role="roles/compute.osLogin"
```

### SSH via IAP (No Public IP Required)

```bash
# SSH directly through IAP tunnel
gcloud compute ssh $VM_NAME \
  --zone $ZONE \
  --tunnel-through-iap

# Port forward JupyterLab (8888) through IAP
gcloud compute ssh $VM_NAME \
  --zone $ZONE \
  --tunnel-through-iap \
  -- -L 8888:localhost:8888 -N &

# Access JupyterLab at: http://localhost:8888
```

### Store Secrets in Secret Manager

```bash
# Store Hugging Face token
echo -n "hf_your_token_here" | gcloud secrets create sandbox-huggingface-token \
  --data-file=- \
  --replication-policy automatic

# Grant access to service account
gcloud secrets add-iam-policy-binding sandbox-huggingface-token \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"
```

---

## Hardening Steps

### 1. Install and Configure GPU Drivers

```bash
# SSH into the instance
gcloud compute ssh $VM_NAME --zone $ZONE --tunnel-through-iap

# Verify NVIDIA driver (should be pre-installed on DL image)
nvidia-smi

# Install NVIDIA Container Toolkit for Docker
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 2. OS Hardening

```bash
# Automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure --priority=low unattended-upgrades

# Enable auditd
sudo apt install -y auditd
sudo systemctl enable --now auditd

# Install and configure fail2ban
sudo apt install -y fail2ban
sudo systemctl enable --now fail2ban

# Disable password SSH auth (OS Login handles auth)
sudo sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Enable kernel security modules
sudo apt install -y apparmor apparmor-utils
sudo systemctl enable --now apparmor
```

### 3. Install Cloud Logging Agent

```bash
# Install Google Cloud Ops Agent
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
sudo bash add-google-cloud-ops-agent-repo.sh --also-install

# Verify
sudo systemctl status google-cloud-ops-agent
```

### 4. Configure Auto-Shutdown

```bash
# Create Cloud Scheduler + Cloud Function for auto-shutdown on idle
# Simpler option: cron job on the instance
sudo tee /etc/cron.d/sandbox-autoshutdown << 'EOF'
# Shutdown at 8 PM UTC on weekdays
0 20 * * 1-5 root /sbin/shutdown -h now "Auto-shutdown: business hours ended"
EOF
```

---

## Validation Tests

```bash
# 1. Verify no external IP
EXTERNAL_IP=$(gcloud compute instances describe $VM_NAME \
  --zone $ZONE \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null)
[ -z "$EXTERNAL_IP" ] && echo "✅ No external IP" || echo "❌ External IP: $EXTERNAL_IP"

# 2. Verify service account attached
SA=$(gcloud compute instances describe $VM_NAME \
  --zone $ZONE \
  --format="value(serviceAccounts[0].email)")
[ "$SA" = "$SA_EMAIL" ] && echo "✅ Service account attached" || echo "❌ SA mismatch: $SA"

# 3. Verify GPU
GPU=$(gcloud compute instances describe $VM_NAME \
  --zone $ZONE \
  --format="value(guestAccelerators[0].acceleratorType)")
[ -n "$GPU" ] && echo "✅ GPU attached: $GPU" || echo "❌ No GPU"

# 4. Test IAP SSH
gcloud compute ssh $VM_NAME --zone $ZONE --tunnel-through-iap \
  --command="nvidia-smi --query-gpu=name --format=csv,noheader" && \
  echo "✅ GPU accessible via IAP SSH" || echo "❌ IAP SSH failed"

# 5. Test Secret Manager access (from instance)
gcloud compute ssh $VM_NAME --zone $ZONE --tunnel-through-iap \
  --command="gcloud secrets versions access latest --secret=sandbox-huggingface-token 2>&1 | head -c 10" && \
  echo "✅ Secret Manager accessible" || echo "❌ Secret Manager access failed"

# 6. Test Cloud Storage access (from instance)
gcloud compute ssh $VM_NAME --zone $ZONE --tunnel-through-iap \
  --command="gcloud storage ls gs://$BUCKET_NAME" && \
  echo "✅ Cloud Storage accessible" || echo "❌ Storage access failed"
```

---

## Troubleshooting

### Issue: GPU quota is 0

**Solutions**:
1. Check current quota: `gcloud compute regions describe $REGION --format="table(quotas.metric,quotas.limit,quotas.usage)" | grep -i nvidia`
2. Request increase: GCP Console → IAM & Admin → Quotas → Search "NVIDIA_T4_GPUS" → Edit
3. Try a different zone within the same region (quota is regional, but capacity varies)
4. Try a different GPU type: L4 often has better availability than T4

### Issue: IAP SSH tunnel connection refused

**Solutions**:
1. Verify IAP API is enabled: `gcloud services list --enabled | grep iap`
2. Check firewall rule for IAP: `gcloud compute firewall-rules describe allow-iap-ssh`
3. Verify you have `roles/iap.tunnelResourceAccessor` on the project
4. Ensure OS Login is enabled: `gcloud compute instances describe $VM_NAME --format="value(metadata.items[enable-oslogin])"`

### Issue: Service account lacks permissions

**Solutions**:
```bash
# List current bindings
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten="bindings[].members" \
  --filter="bindings.members:serviceAccount:${SA_EMAIL}" \
  --format="table(bindings.role)"

# Add missing role
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/MISSING_ROLE"
```

### Issue: Preemptible/Spot VM was terminated unexpectedly

**Solutions**:
1. Check instance status: `gcloud compute instances describe $VM_NAME --zone $ZONE --format="value(status)"`
2. Review audit logs for termination event: `gcloud logging read "resource.type=gce_instance AND protoPayload.methodName=v1.compute.instances.delete" --limit 10`
3. Restart and restore from latest checkpoint on Cloud Storage
4. Consider switching to non-preemptible for critical experiments

### Issue: Terraform provider authentication fails

**Solutions**:
```bash
# Refresh application default credentials
gcloud auth application-default login

# Or set explicit credentials file
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account-key.json"

# Verify terraform can connect
terraform plan
```
