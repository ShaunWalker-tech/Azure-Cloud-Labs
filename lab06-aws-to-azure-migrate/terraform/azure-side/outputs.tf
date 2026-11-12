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

# Uncomment together with the discovery appliance section in main.tf.
# output "appliance_public_ip" {
#   value = azurerm_public_ip.appliance.ip_address
# }

output "replication_appliance_public_ip" {
  value = azurerm_public_ip.replication.ip_address
}
