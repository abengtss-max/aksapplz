locals {
  firewall_name           = var.firewall_name != "" ? var.firewall_name : "afw-${var.vnet_name}"
  firewall_public_ip_name = var.firewall_public_ip_name != "" ? var.firewall_public_ip_name : "pip-${local.firewall_name}"
  firewall_policy_name    = var.firewall_policy_name != "" ? var.firewall_policy_name : "afwp-${var.vnet_name}"
}

resource "azurerm_resource_group" "hub" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# AzureFirewallSubnet is always created (whether or not we deploy the firewall),
# so spokes can be peered immediately and the firewall added later without
# destroying the VNet.
resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.firewall_subnet_address_prefix]
}

resource "azurerm_public_ip" "firewall" {
  count               = var.deploy_firewall ? 1 : 0
  name                = local.firewall_public_ip_name
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_firewall_policy" "hub" {
  count                    = var.deploy_firewall ? 1 : 0
  name                     = local.firewall_policy_name
  resource_group_name      = azurerm_resource_group.hub.name
  location                 = azurerm_resource_group.hub.location
  sku                      = var.firewall_sku_tier
  threat_intelligence_mode = "Deny" # Actively block known-malicious traffic (valid on Standard and Premium tiers).
  tags                     = var.tags
}

resource "azurerm_firewall" "hub" {
  count               = var.deploy_firewall ? 1 : 0
  name                = local.firewall_name
  resource_group_name = azurerm_resource_group.hub.name
  location            = azurerm_resource_group.hub.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.hub[0].id
  zones               = ["1", "2", "3"]
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall[0].id
  }
}
