variable "aws_region" {
  description = "AWS region for the source server."
  type        = string
  default     = "us-east-1"
}

variable "yourname" {
  description = "Short name used in every resource name (e.g. vpc-migrate-<yourname>)."
  type        = string
}

variable "windows_ami" {
  description = "Current Windows Server 2022 Base AMI for the region. See README for the lookup command."
  type        = string
}

variable "instance_type" {
  description = "EC2 size for the source server."
  type        = string
  default     = "t3.medium"
}

variable "admin_password" {
  description = "Administrator password set at first boot. 12+ chars; use only letters, numbers, #, ! or @."
  type        = string
  sensitive   = true
}

variable "admin_cidrs" {
  description = "Who may reach RDP (3389) and HTTPS (443). The lab ran with 0.0.0.0/0; set your own IP/32 instead."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "winrm_allowed_cidrs" {
  description = "Public IP(s) of the Azure Migrate appliance(s), as /32s. Leave empty until the appliance exists."
  type        = list(string)
  default     = []
}
