output "source_resource_group" {
  value = azurerm_resource_group.source.name
}

output "target_resource_group" {
  value = azurerm_resource_group.target.name
}

output "replication_storage_account" {
  value = azurerm_storage_account.replication_cache.name
}

output "target_subnet_id" {
  value = azurerm_subnet.main.id
}

output "appliance_public_ip" {
  description = "Discovery appliance IP. Add it to aws-side winrm_allowed_cidrs as a /32."
  value       = azurerm_public_ip.appliance.ip_address
}

output "replication_appliance_public_ip" {
  description = "Replication appliance IP. Swap it into aws-side winrm_allowed_cidrs in Phase 5."
  value       = try(azurerm_public_ip.replication[0].ip_address, null)
}
