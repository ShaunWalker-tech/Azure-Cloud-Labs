# -----------------------------------------------------------------------------
# AWS side: the "old house"
# A Windows Server 2022 EC2 instance in its own VPC, which Azure Migrate
# discovers, replicates, and moves into Azure.
# -----------------------------------------------------------------------------

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# --- Network -----------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16" # Azure uses 10.1.0.0/16, so the two never overlap
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "vpc-migrate-${var.yourname}", project = "azure-migrate-lab" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "igw-migrate-${var.yourname}" }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = { Name = "snet-migrate-${var.yourname}" }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "rt-migrate-${var.yourname}" }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# --- Security group ----------------------------------------------------------
# Name must not start with "sg-" (AWS rejects it).

resource "aws_security_group" "source_vm" {
  name        = "migrate-source-sg-${var.yourname}"
  description = "Allow HTTPS and RDP for Azure Migrate lab"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }

  ingress {
    description = "RDP for admin access"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = var.admin_cidrs
  }

  # WinRM is how the Azure Migrate appliances log in to inventory the server.
  # Opened only to the appliance IP(s), never to the internet.
  dynamic "ingress" {
    for_each = length(var.winrm_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "WinRM from the Azure Migrate appliance"
      from_port   = 5985
      to_port     = 5985
      protocol    = "tcp"
      cidr_blocks = var.winrm_allowed_cidrs
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "migrate-source-sg-${var.yourname}" }
}

# --- IAM for Azure Migrate (from the lab guide) ------------------------------
# Read-only EC2 permissions plus snapshot create/delete. The service user and
# key below were created by the guide but not needed for the physical-server
# path this lab used. See docs/troubleshooting.md and the README.

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "migrate_permissions" {
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances", "ec2:DescribeInstanceTypes", "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots", "ec2:DescribeImages", "ec2:DescribeRegions",
      "ec2:CreateSnapshot", "ec2:DeleteSnapshot", "ec2:DescribeTags"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "migrate_role" {
  name               = "role-azure-migrate-${var.yourname}"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_iam_policy" "migrate_policy" {
  name   = "policy-azure-migrate-${var.yourname}"
  policy = data.aws_iam_policy_document.migrate_permissions.json
}

resource "aws_iam_role_policy_attachment" "migrate_attach" {
  role       = aws_iam_role.migrate_role.name
  policy_arn = aws_iam_policy.migrate_policy.arn
}

resource "aws_iam_instance_profile" "migrate_profile" {
  name = "profile-azure-migrate-${var.yourname}"
  role = aws_iam_role.migrate_role.name
}

resource "aws_iam_user" "migrate_user" {
  name = "svc-azure-migrate-${var.yourname}"
}

resource "aws_iam_user_policy_attachment" "migrate_user_policy" {
  user       = aws_iam_user.migrate_user.name
  policy_arn = aws_iam_policy.migrate_policy.arn
}

# WARNING: this secret is written to terraform.tfstate in plain text.
# terraform.tfstate is git-ignored for exactly this reason.
resource "aws_iam_access_key" "migrate_user_key" {
  user = aws_iam_user.migrate_user.name
}

# --- The source server -------------------------------------------------------

resource "aws_instance" "source_vm" {
  ami                    = var.windows_ami
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.main.id
  vpc_security_group_ids = [aws_security_group.source_vm.id]
  iam_instance_profile   = aws_iam_instance_profile.migrate_profile.name

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = false
  }

  # Runs on FIRST boot only. Avoid $, " and ` in the password: they break this
  # script and nobody can log in. To change the password later:
  #   terraform apply -replace="aws_instance.source_vm"
  user_data = <<-EOF
    <powershell>
    net user Administrator "${var.admin_password}"
    </powershell>
  EOF

  volume_tags = { Name = "vol-migrate-source-${var.yourname}", project = "azure-migrate-lab" }
  tags        = { Name = "ec2-migrate-source-${var.yourname}", project = "azure-migrate-lab" }
}
