locals {
  pdz_configs = var.use_private_networking ? {
    blob = "privatelink.blob.core.windows.net"
    acr  = "privatelink.azurecr.io"
  } : {}
}

module "private_dns_zone" {
  source   = "Azure/avm-res-network-privatednszone/azurerm"
  version  = "~> 0.5"
  for_each = local.pdz_configs

  domain_name      = each.value
  parent_id        = azurerm_resource_group.network[0].id
  enable_telemetry = false
  tags             = var.tags

  virtual_network_links = {
    spoke = {
      vnetlinkname = "vnetlink-${each.key}-bootstrap"
      vnetid       = module.virtual_network[0].resource_id
    }
  }
}

resource "azurerm_private_endpoint" "storage_blob" {
  count               = var.use_private_networking ? 1 : 0
  name                = var.resource_names["storage_account_private_endpoint"]
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.network[0].name
  subnet_id           = module.virtual_network[0].subnets["private_endpoints"].resource_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.resource_names["storage_account"]}-blob"
    private_connection_resource_id = module.storage_account.resource_id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "blob"
    private_dns_zone_ids = [module.private_dns_zone["blob"].resource_id]
  }
}

resource "azurerm_private_endpoint" "container_registry" {
  count               = var.use_private_networking && var.use_self_hosted_runners ? 1 : 0
  name                = var.resource_names["container_registry_private_endpoint"]
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.network[0].name
  subnet_id           = module.virtual_network[0].subnets["private_endpoints"].resource_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.resource_names["container_registry"]}-registry"
    private_connection_resource_id = module.container_registry[0].resource_id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "registry"
    private_dns_zone_ids = [module.private_dns_zone["acr"].resource_id]
  }
}
