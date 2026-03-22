terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# --- Data Sources ---

data "google_client_config" "current" {}

data "google_project" "sandbox" {
  project_id = var.project_id
}

# --- Enable Required APIs ---

resource "google_project_service" "apis" {
  for_each = toset([
    "compute.googleapis.com",
    "iam.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "iap.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# --- VPC Network ---

resource "google_compute_network" "sandbox" {
  name                    = "vpc-${var.project_name}-${var.environment}"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "AI sandbox VPC network — isolated from production"

  depends_on = [google_project_service.apis]
}

resource "google_compute_subnetwork" "sandbox" {
  name                     = "subnet-${var.project_name}-${var.environment}"
  network                  = google_compute_network.sandbox.id
  region                   = var.region
  ip_cidr_range            = var.subnet_cidr
  private_ip_google_access = true  # Access Google APIs without external IP

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# --- Firewall Rules ---

# Allow SSH via Identity-Aware Proxy
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "allow-iap-ssh-${var.project_name}"
  network     = google_compute_network.sandbox.id
  description = "Allow SSH via Identity-Aware Proxy tunneling"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]  # Google IAP IP range
  target_tags   = ["ai-sandbox"]
}

# Allow internal VPC traffic
resource "google_compute_firewall" "allow_internal" {
  name        = "allow-internal-${var.project_name}"
  network     = google_compute_network.sandbox.id
  description = "Allow all traffic within the sandbox VPC"

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["ai-sandbox"]
}

# Allow JupyterLab from approved CIDR ranges
resource "google_compute_firewall" "allow_jupyterlab" {
  count       = length(var.allowed_cidr_ranges) > 0 ? 1 : 0
  name        = "allow-jupyterlab-${var.project_name}"
  network     = google_compute_network.sandbox.id
  description = "Allow JupyterLab access from approved IP ranges (VPN, bastion)"

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  source_ranges = var.allowed_cidr_ranges
  target_tags   = ["ai-sandbox"]
}

# Deny all other ingress explicitly
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "deny-all-ingress-${var.project_name}"
  network     = google_compute_network.sandbox.id
  description = "Deny all ingress not explicitly allowed"
  priority    = 65534

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["ai-sandbox"]
}

# --- Cloud Router and NAT (for controlled egress) ---

resource "google_compute_router" "sandbox" {
  count   = var.enable_cloud_nat ? 1 : 0
  name    = "router-${var.project_name}"
  network = google_compute_network.sandbox.id
  region  = var.region
}

resource "google_compute_router_nat" "sandbox" {
  count                              = var.enable_cloud_nat ? 1 : 0
  name                               = "nat-${var.project_name}"
  router                             = google_compute_router.sandbox[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# --- Service Account ---

resource "google_service_account" "sandbox" {
  account_id   = "sa-${var.project_name}-${var.environment}"
  display_name = "AI Sandbox Service Account"
  description  = "Service account for ${var.project_name} sandbox VM instances"
}

# --- IAM Bindings for Service Account ---

# Cloud Storage access (sandbox bucket only)
resource "google_storage_bucket_iam_member" "sandbox_storage" {
  bucket = google_storage_bucket.sandbox.name
  role   = "roles/storage.objectUser"
  member = "serviceAccount:${google_service_account.sandbox.email}"
}

# Secret Manager access
resource "google_project_iam_member" "sandbox_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

# Logging and monitoring
resource "google_project_iam_member" "sandbox_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

resource "google_project_iam_member" "sandbox_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.sandbox.email}"
}

# --- Cloud Storage Bucket ---

resource "random_string" "bucket_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "google_storage_bucket" "sandbox" {
  name          = "${var.project_name}-models-${var.project_id}"
  location      = upper(var.region)
  force_destroy = false

  # Security settings
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }

  # Lifecycle rules
  lifecycle_rule {
    condition {
      age        = 30
      with_state = "LIVE"
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age        = 90
      with_state = "LIVE"
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  # Soft delete policy
  soft_delete_policy {
    retention_duration_seconds = 604800  # 7 days
  }

  labels = {
    environment = var.environment
    project     = var.project_name
    managed-by  = "terraform"
  }
}

# --- Compute Instance ---

resource "google_compute_instance" "sandbox" {
  name         = "vm-${var.project_name}-${var.environment}"
  machine_type = var.machine_type
  zone         = var.zone

  tags   = ["ai-sandbox"]
  labels = {
    environment = var.environment
    project     = var.project_name
    team        = var.team_name
    managed-by  = "terraform"
  }

  # GPU configuration (conditional)
  dynamic "guest_accelerator" {
    for_each = var.gpu_count > 0 ? [1] : []
    content {
      type  = var.gpu_type
      count = var.gpu_count
    }
  }

  # Required for GPU instances
  scheduling {
    on_host_maintenance = var.gpu_count > 0 ? "TERMINATE" : "MIGRATE"
    automatic_restart   = var.use_spot_vm ? false : true
    preemptible         = var.use_spot_vm
    provisioning_model  = var.use_spot_vm ? "SPOT" : "STANDARD"

    dynamic "node_affinities" {
      for_each = []  # Reserved for sole-tenant nodes
      content {
        key      = node_affinities.value.key
        operator = node_affinities.value.operator
        values   = node_affinities.value.values
      }
    }
  }

  boot_disk {
    initialize_params {
      image  = var.boot_disk_image
      size   = var.boot_disk_size_gb
      type   = "pd-ssd"
    }
    auto_delete = true
  }

  # Data disk for models and datasets
  attached_disk {
    source      = google_compute_disk.data.id
    device_name = "sandbox-data"
    mode        = "READ_WRITE"
  }

  # No external IP
  network_interface {
    subnetwork = google_compute_subnetwork.sandbox.id
    # No access_config block = no external IP
  }

  # Service account
  service_account {
    email  = google_service_account.sandbox.email
    scopes = ["cloud-platform"]
  }

  # Enable OS Login (replaces SSH key management)
  metadata = {
    enable-oslogin         = "TRUE"
    enable-oslogin-2fa     = "FALSE"
    serial-port-logging-enable = "TRUE"
    startup-script = templatefile("${path.module}/startup-script.sh.tpl", {
      data_bucket = google_storage_bucket.sandbox.name
      project_id  = var.project_id
    })
  }

  # Shielded VM options (enhanced security)
  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [
    google_project_service.apis,
    google_compute_disk.data,
  ]
}

# --- Data Disk ---

resource "google_compute_disk" "data" {
  name  = "disk-data-${var.project_name}-${var.environment}"
  type  = "pd-ssd"
  zone  = var.zone
  size  = var.data_disk_size_gb

  labels = {
    environment = var.environment
    project     = var.project_name
  }
}

# --- IAP Access for Developers ---

resource "google_iap_tunnel_instance_iam_member" "developer_access" {
  for_each = toset(var.developer_emails)

  project  = var.project_id
  zone     = var.zone
  instance = google_compute_instance.sandbox.name
  role     = "roles/iap.tunnelResourceAccessor"
  member   = "user:${each.value}"
}

# --- OS Login for Developers ---

resource "google_project_iam_member" "os_login" {
  for_each = toset(var.developer_emails)

  project = var.project_id
  role    = "roles/compute.osLogin"
  member  = "user:${each.value}"
}
