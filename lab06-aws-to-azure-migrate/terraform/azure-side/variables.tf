variable "yourname" {
  description = "Short name used in every resource name (e.g. rg-migrate-source-<yourname>)."
  type        = string
}

variable "location" {
  description = "Azure region. Check capacity first: az vm list-skus --location <region> --size <sku> --all -o table"
  type        = string
  default     = "Central US"
}

variable "tags" {
  type = map(string)
  default = {
    project    = "azure-migrate-lab"
    managed_by = "terraform"
  }
}

variable "appliance_admin_password" {
  description = "Local admin password for the discovery appliance VM."
  type        = string
  sensitive   = true
}

variable "replication_admin_password" {
  description = "Local admin password for the replication appliance VM."
  type        = string
  sensitive   = true
}

variable "admin_source_prefix" {
  description = "Who may RDP to the Azure VMs. The lab ran with \"*\"; set your own IP instead."
  type        = string
  default     = "*"
}

variable "deploy_discovery_appliance" {
  description = "Phase 3-4: true. Set false before Phase 5 to free vCPU quota."
  type        = bool
  default     = true
}

variable "deploy_replication_appliance" {
  description = "Phase 5-6: true. Needs ~16 vCPUs of quota in the region."
  type        = bool
  default     = false
}

variable "ec2_public_ip" {
  description = "EC2 public IP (aws-side output ec2_public_ip). Locks the 9443 replication rule to that one address."
  type        = string
  default     = ""
}
