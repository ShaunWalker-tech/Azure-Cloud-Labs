variable "yourname" {
  type = string
}

variable "location" {
  type    = string
  default = "Central US"
}

variable "tags" {
  type = map(string)
  default = {
    project    = "azure-migrate-lab"
    managed_by = "terraform"
  }
}

variable "appliance_admin_password" {
  description = "Local admin password for the discovery appliance VM"
  type        = string
  sensitive   = true
}

variable "replication_admin_password" {
  description = "Local admin password for the replication appliance VM"
  type        = string
  sensitive   = true
}

variable "ec2_public_ip" {
  description = "Public IP of the EC2 source server, allowed to send replication data on 9443"
  type        = string
}
