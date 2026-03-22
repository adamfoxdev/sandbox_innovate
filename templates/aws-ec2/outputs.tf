output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.sandbox.id
}

output "subnet_id" {
  description = "ID of the private sandbox subnet"
  value       = aws_subnet.sandbox_private.id
}

output "security_group_id" {
  description = "ID of the sandbox security group"
  value       = aws_security_group.sandbox.id
}

output "instance_id" {
  description = "ID of the sandbox EC2 instance"
  value       = aws_instance.sandbox.id
}

output "instance_private_ip" {
  description = "Private IP address of the sandbox instance (no public IP)"
  value       = aws_instance.sandbox.private_ip
}

output "instance_type" {
  description = "EC2 instance type"
  value       = aws_instance.sandbox.instance_type
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the sandbox instance"
  value       = aws_iam_role.sandbox.arn
}

output "iam_instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.sandbox.arn
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket for models and artifacts"
  value       = aws_s3_bucket.sandbox.bucket
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket"
  value       = aws_s3_bucket.sandbox.arn
}

output "ami_id" {
  description = "AMI ID used for the sandbox instance (Deep Learning AMI)"
  value       = data.aws_ami.deep_learning.id
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}

output "connection_instructions" {
  description = "Instructions for connecting to the sandbox via SSM"
  value       = <<-EOT
    Sandbox EC2 instance provisioned successfully!

    Instance ID:  ${aws_instance.sandbox.id}
    Private IP:   ${aws_instance.sandbox.private_ip}
    Instance Type: ${aws_instance.sandbox.instance_type}
    S3 Bucket:    ${aws_s3_bucket.sandbox.bucket}

    Connect via SSM Session Manager (no SSH port required):
      aws ssm start-session --target ${aws_instance.sandbox.id} --region ${var.region}

    Port-forward JupyterLab:
      aws ssm start-session \
        --target ${aws_instance.sandbox.id} \
        --document-name AWS-StartPortForwardingSession \
        --parameters portNumber=8888,localPortNumber=8888 \
        --region ${var.region}

    Then access JupyterLab at: http://localhost:8888

    Sync models to S3:
      aws s3 cp ./my-model s3://${aws_s3_bucket.sandbox.bucket}/models/my-model/ --recursive
  EOT
}
