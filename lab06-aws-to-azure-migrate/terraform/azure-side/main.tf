terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "source" {
  name     = "rg-migrate-source-${var.yourname}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-migrate-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.source.name
  address_space       = ["10.1.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "main" {
  name                 = "snet-migrate"
  resource_group_name  = azurerm_resource_group.source.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_resource_group" "target" {
  name     = "rg-migrate-target-${var.yourname}"
  location = var.location
  tags     = var.tags
}

# Azure Migrate projects can't be made with Terraform.
# The project was created by hand in the portal.
resource "null_resource" "migrate_project_reminder" {
  triggers = {
    resource_group = azurerm_resource_group.source.name
  }
}

# Storage account names must be unique across all of Azure.
resource "azurerm_storage_account" "replication_cache" {
  name                     = "stmigrate${var.yourname}"
  resource_group_name      = azurerm_resource_group.source.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"
  min_tls_version          = "TLS1_2"
  tags                     = var.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-migrate-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.source.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_recovery_services_vault" "main" {
  name                         = "rsv-migrate-${var.yourname}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.source.name
  sku                          = "Standard"
  soft_delete_enabled          = true # Azure no longer allows false on new vaults
  cross_region_restore_enabled = false
  tags                         = var.tags
}

# Attached to the migrated VM's NIC after cutover so RDP works.
resource "azurerm_network_security_group" "target_vm" {
  name                = "nsg-migrate-target-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.target.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Discovery appliance (Phase 3)
# Used for discovery and the assessment, then commented out in Phase 5 to free
# vCPU quota for the replication appliance. Uncomment this whole section, plus
# the appliance_public_ip output in outputs.tf, to rebuild it.
# -----------------------------------------------------------------------------

# resource "azurerm_public_ip" "appliance" {
#   name                = "pip-migrate-appliance-${var.yourname}"
#   location            = var.location
#   resource_group_name = azurerm_resource_group.source.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
#   tags                = var.tags
# }
#
# resource "azurerm_network_interface" "appliance" {
#   name                = "nic-migrate-appliance-${var.yourname}"
#   location            = var.location
#   resource_group_name = azurerm_resource_group.source.name
#   ip_configuration {
#     name                          = "internal"
#     subnet_id                     = azurerm_subnet.main.id
#     private_ip_address_allocation = "Dynamic"
#     public_ip_address_id          = azurerm_public_ip.appliance.id
#   }
#   tags = var.tags
# }
#
# resource "azurerm_network_security_group" "appliance" {
#   name                = "nsg-migrate-appliance-${var.yourname}"
#   location            = var.location
#   resource_group_name = azurerm_resource_group.source.name
#   security_rule {
#     name                       = "allow-rdp"
#     priority                   = 1000
#     direction                  = "Inbound"
#     access                     = "Allow"
#     protocol                   = "Tcp"
#     source_port_range          = "*"
#     destination_port_range     = "3389"
#     source_address_prefix      = "*"
#     destination_address_prefix = "*"
#   }
#   tags = var.tags
# }
#
# resource "azurerm_network_interface_security_group_association" "appliance" {
#   network_interface_id      = azurerm_network_interface.appliance.id
#   network_security_group_id = azurerm_network_security_group.appliance.id
# }
#
# resource "azurerm_windows_virtual_machine" "appliance" {
#   name                  = "vm-mig-appl-${var.yourname}"
#   computer_name         = "appl-${var.yourname}" # Windows max is 15 characters
#   location              = var.location
#   resource_group_name   = azurerm_resource_group.source.name
#   size                  = "Standard_D4als_v7" # older sizes are blocked on this subscription
#   admin_username        = "migrateadmin"
#   admin_password        = var.appliance_admin_password
#   network_interface_ids = [azurerm_network_interface.appliance.id]
#   os_disk {
#     caching              = "ReadWrite"
#     storage_account_type = "Standard_LRS"
#     disk_size_gb         = 127 # can't be smaller than the image's 127 GB
#   }
#   source_image_reference {
#     publisher = "MicrosoftWindowsServer"
#     offer     = "WindowsServer"
#     sku       = "2022-datacenter-g2" # v7 sizes need a Gen2 image
#     version   = "latest"
#   }
#   tags = var.tags
# }

# -----------------------------------------------------------------------------
# Replication appliance (Phase 5)
# -----------------------------------------------------------------------------

resource "azurerm_public_ip" "replication" {
  name                = "pip-migrate-repl-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.source.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "replication" {
  name                = "nic-migrate-repl-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.source.name
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.replication.id
  }
  tags = var.tags
}

resource "azurerm_network_security_group" "replication" {
  name                = "nsg-migrate-repl-${var.yourname}"
  location            = var.location
  resource_group_name = azurerm_resource_group.source.name

  security_rule {
    name                       = "allow-rdp"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-inbound"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # The Mobility agent on the EC2 server sends disk data on 9443.
  security_rule {
    name                       = "allow-replication-data"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "9443"
    source_address_prefix      = "${var.ec2_public_ip}/32"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

resource "azurerm_network_interface_security_group_association" "replication" {
  network_interface_id      = azurerm_network_interface.replication.id
  network_security_group_id = azurerm_network_security_group.replication.id
}

resource "azurerm_windows_virtual_machine" "replication" {
  name                  = "vm-mig-repl-${var.yourname}"
  computer_name         = "repl-${var.yourname}"
  location              = var.location
  resource_group_name   = azurerm_resource_group.source.name
  size                  = "Standard_D16as_v7" # 16 vCPUs; needed a vCPU quota increase
  admin_username        = "replicationadmin"
  admin_password        = var.replication_admin_password
  network_interface_ids = [azurerm_network_interface.replication.id]
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 700
  }
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2" # v7 sizes need a Gen2 image
    version   = "latest"
  }
  tags = var.tags
}
