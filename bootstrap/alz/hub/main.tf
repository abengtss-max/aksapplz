locals {
  location_short_map = {
    swedencentral      = "sc"
    westeurope         = "we"
    northeurope        = "ne"
    eastus             = "eus"
    eastus2            = "eus2"
    westus2            = "wus2"
    westus3            = "wus3"
    centralus          = "cus"
    uksouth            = "uks"
    ukwest             = "ukw"
    germanywestcentral = "gwc"
    francecentral      = "frc"
    norwayeast         = "noe"
    switzerlandnorth   = "swn"
  }
  location_short = lookup(local.location_short_map, var.location, substr(replace(var.location, "/[^a-z]/", ""), 0, 4))
  postfix        = format("%03d", var.postfix_number)
  default_tags = {
    managedBy   = "aksapplz-bootstrap-terraform"
    service     = var.service_name
    environment = var.environment_name
    role        = "connectivity-hub"
  }
  resource_group_name = "rg-${var.service_name}-${var.environment_name}-hub-${local.location_short}-${local.postfix}"
  vnet_name           = "vnet-${var.service_name}-${var.environment_name}-hub-${local.location_short}-${local.postfix}"
}

module "hub" {
  source = "../../modules/azure_hub"

  location                       = var.location
  resource_group_name            = local.resource_group_name
  vnet_name                      = local.vnet_name
  vnet_address_space             = var.hub_vnet_address_space
  deploy_firewall                = var.deploy_firewall
  firewall_sku_tier              = var.firewall_sku_tier
  firewall_subnet_address_prefix = var.firewall_subnet_address_prefix
  tags                           = merge(local.default_tags, var.tags)
}
