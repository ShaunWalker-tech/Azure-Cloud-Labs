variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "yourname" {
  type = string
}

variable "windows_ami" {
  description = "Current Windows Server 2022 AMI in this region (see README for the lookup command)"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "admin_password" {
  description = "Windows Administrator password for the EC2 server (also used on the migrated Azure VM)"
  type        = string
  sensitive   = true
}

variable "migrate_appliance_ip" {
  description = "Public IP of the Azure Migrate appliance allowed to reach WinRM, SMB and WMI"
  type        = string
}
