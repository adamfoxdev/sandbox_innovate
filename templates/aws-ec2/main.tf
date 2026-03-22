terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.30"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      Team        = var.team_name
      ManagedBy   = "terraform"
    }
  }
}

# --- Data Sources ---

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "deep_learning" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Deep Learning AMI GPU PyTorch * (Ubuntu 22.04) *"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- VPC ---

resource "aws_vpc" "sandbox" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "vpc-${var.project_name}-${var.environment}"
  }
}

# --- Private Subnet ---

resource "aws_subnet" "sandbox_private" {
  vpc_id                  = aws_vpc.sandbox.id
  cidr_block              = var.private_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "subnet-${var.project_name}-private"
    Type = "private"
  }
}

# --- Route Table ---

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sandbox.id

  tags = {
    Name = "rt-${var.project_name}-private"
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.sandbox_private.id
  route_table_id = aws_route_table.private.id
}

# --- VPC Endpoints ---

# S3 Gateway Endpoint (free — required for efficient S3 access without internet)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.sandbox.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "vpce-s3-${var.project_name}"
  }
}

# SSM Endpoint (required for Session Manager without internet)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.sandbox.id
  service_name        = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.sandbox_private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ssm-${var.project_name}"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.sandbox.id
  service_name        = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.sandbox_private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ssmmessages-${var.project_name}"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.sandbox.id
  service_name        = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.sandbox_private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-ec2messages-${var.project_name}"
  }
}

# Secrets Manager Endpoint
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.sandbox.id
  service_name        = "com.amazonaws.${var.region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.sandbox_private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "vpce-secretsmanager-${var.project_name}"
  }
}

# --- Security Group: VPC Endpoints ---

resource "aws_security_group" "vpce" {
  name        = "sg-vpce-${var.project_name}"
  description = "Security group for VPC interface endpoints"
  vpc_id      = aws_vpc.sandbox.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "HTTPS from within VPC"
  }

  tags = {
    Name = "sg-vpce-${var.project_name}"
  }
}

# --- Security Group: Sandbox Instances ---

resource "aws_security_group" "sandbox" {
  name        = "sg-${var.project_name}-${var.environment}"
  description = "Security group for AI sandbox instances. No public ingress."
  vpc_id      = aws_vpc.sandbox.id

  ingress {
    from_port   = 8888
    to_port     = 8888
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_ranges
    description = "JupyterLab access from approved ranges"
  }

  ingress {
    from_port   = 11434
    to_port     = 11434
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
    description = "Ollama API from within VPC"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound (filtered by VPC endpoints and route table)"
  }

  tags = {
    Name = "sg-${var.project_name}-${var.environment}"
  }
}

# --- IAM Role and Instance Profile ---

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sandbox" {
  name               = "role-${var.project_name}-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name = "role-${var.project_name}-${var.environment}"
  }
}

# Attach SSM policy for Session Manager access
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.sandbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach CloudWatch agent policy
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.sandbox.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Custom policy for sandbox resources
data "aws_iam_policy_document" "sandbox_custom" {
  statement {
    sid    = "AllowS3SandboxBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.sandbox.arn,
      "${aws_s3_bucket.sandbox.arn}/*",
    ]
  }

  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/*",
    ]
  }

  statement {
    sid    = "AllowCloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sandbox_custom" {
  name   = "policy-sandbox-custom"
  role   = aws_iam_role.sandbox.id
  policy = data.aws_iam_policy_document.sandbox_custom.json
}

resource "aws_iam_instance_profile" "sandbox" {
  name = "profile-${var.project_name}-${var.environment}"
  role = aws_iam_role.sandbox.name

  tags = {
    Name = "profile-${var.project_name}-${var.environment}"
  }
}

# --- S3 Bucket for Models and Artifacts ---

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "aws_s3_bucket" "sandbox" {
  bucket = "${var.project_name}-models-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_name}-models"
    Purpose = "AI model weights, datasets, and experiment artifacts"
  }
}

resource "aws_s3_bucket_public_access_block" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sandbox" {
  bucket = aws_s3_bucket.sandbox.id

  rule {
    id     = "models-lifecycle"
    status = "Enabled"

    filter {
      prefix = "models/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  rule {
    id     = "outputs-lifecycle"
    status = "Enabled"

    filter {
      prefix = "outputs/"
    }

    expiration {
      days = 90
    }
  }
}

# --- EC2 Instance ---

resource "aws_instance" "sandbox" {
  ami                    = data.aws_ami.deep_learning.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.sandbox_private.id
  vpc_security_group_ids = [aws_security_group.sandbox.id]
  iam_instance_profile   = aws_iam_instance_profile.sandbox.name

  # No public IP
  associate_public_ip_address = false

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "osdisk-${var.project_name}-${var.environment}"
    }
  }

  ebs_block_device {
    device_name           = "/dev/sdb"
    volume_type           = "gp3"
    volume_size           = var.data_volume_size_gb
    encrypted             = true
    delete_on_termination = false

    tags = {
      Name = "datadisk-${var.project_name}-${var.environment}"
    }
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh.tpl", {
    s3_bucket = aws_s3_bucket.sandbox.bucket
    region    = var.region
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 required
    http_put_response_hop_limit = 1
  }

  monitoring = true  # Detailed CloudWatch monitoring

  tags = {
    Name = "vm-${var.project_name}-${var.environment}"
  }
}

# --- CloudWatch Auto-Shutdown Alarm ---

resource "aws_cloudwatch_metric_alarm" "idle_shutdown" {
  count               = var.enable_auto_shutdown ? 1 : 0
  alarm_name          = "alarm-${var.project_name}-idle-shutdown"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "6"   # 6 consecutive periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "300" # 5-minute periods
  statistic           = "Average"
  threshold           = "5"   # < 5% CPU
  alarm_description   = "Sandbox instance is idle — triggering shutdown"

  dimensions = {
    InstanceId = aws_instance.sandbox.id
  }

  alarm_actions = [aws_ssm_document.stop_instance[0].arn]
}

resource "aws_ssm_document" "stop_instance" {
  count         = var.enable_auto_shutdown ? 1 : 0
  name          = "ssm-doc-stop-${var.project_name}"
  document_type = "Automation"

  content = jsonencode({
    schemaVersion = "0.3"
    description   = "Stop idle sandbox instance"
    mainSteps = [{
      name   = "stopInstance"
      action = "aws:changeInstanceState"
      inputs = {
        InstanceIds  = [aws_instance.sandbox.id]
        DesiredState = "stopped"
      }
    }]
  })
}
