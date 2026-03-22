output "project_id" {
  description = "GCP project ID"
  value       = var.project_id
}

output "instance_name" {
  description = "Name of the sandbox compute instance"
  value       = google_compute_instance.sandbox.name
}

output "instance_id" {
  description = "Self-link ID of the sandbox compute instance"
  value       = google_compute_instance.sandbox.id
}

output "instance_self_link" {
  description = "Self-link URI of the sandbox compute instance"
  value       = google_compute_instance.sandbox.self_link
}

output "instance_zone" {
  description = "Zone where the instance is deployed"
  value       = google_compute_instance.sandbox.zone
}

output "instance_machine_type" {
  description = "Machine type of the sandbox instance"
  value       = google_compute_instance.sandbox.machine_type
}

output "instance_internal_ip" {
  description = "Internal IP address of the sandbox instance (no external IP)"
  value       = google_compute_instance.sandbox.network_interface[0].network_ip
}

output "vpc_network_name" {
  description = "Name of the sandbox VPC network"
  value       = google_compute_network.sandbox.name
}

output "subnet_name" {
  description = "Name of the sandbox subnet"
  value       = google_compute_subnetwork.sandbox.name
}

output "subnet_cidr" {
  description = "CIDR range of the sandbox subnet"
  value       = google_compute_subnetwork.sandbox.ip_cidr_range
}

output "service_account_email" {
  description = "Email of the sandbox service account"
  value       = google_service_account.sandbox.email
}

output "storage_bucket_name" {
  description = "Name of the Cloud Storage bucket for models and artifacts"
  value       = google_storage_bucket.sandbox.name
}

output "storage_bucket_url" {
  description = "GCS URL of the sandbox storage bucket"
  value       = "gs://${google_storage_bucket.sandbox.name}"
}

output "iap_ssh_command" {
  description = "Command to SSH into the instance via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.sandbox.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap"
}

output "port_forward_command" {
  description = "Command to port-forward JupyterLab via IAP"
  value       = "gcloud compute ssh ${google_compute_instance.sandbox.name} --project ${var.project_id} --zone ${var.zone} --tunnel-through-iap -- -L 8888:localhost:8888 -N"
}

output "connection_instructions" {
  description = "Complete instructions for accessing the sandbox"
  value       = <<-EOT
    GCP Compute Engine sandbox provisioned successfully!

    Instance:      ${google_compute_instance.sandbox.name}
    Zone:          ${var.zone}
    Machine Type:  ${var.machine_type}
    GPU:           ${var.gpu_count > 0 ? "${var.gpu_count}x ${var.gpu_type}" : "None (CPU only)"}
    Internal IP:   ${google_compute_instance.sandbox.network_interface[0].network_ip}
    Spot VM:       ${var.use_spot_vm}

    Storage Bucket: gs://${google_storage_bucket.sandbox.name}
    Service Account: ${google_service_account.sandbox.email}

    ── Connect via IAP SSH ──
    gcloud compute ssh ${google_compute_instance.sandbox.name} \
      --project ${var.project_id} \
      --zone ${var.zone} \
      --tunnel-through-iap

    ── Port-forward JupyterLab ──
    gcloud compute ssh ${google_compute_instance.sandbox.name} \
      --project ${var.project_id} \
      --zone ${var.zone} \
      --tunnel-through-iap \
      -- -L 8888:localhost:8888 -N &

    Then access: http://localhost:8888

    ── Upload models to Cloud Storage ──
    gcloud storage cp ./my-model gs://${google_storage_bucket.sandbox.name}/models/my-model/ --recursive
  EOT
}
