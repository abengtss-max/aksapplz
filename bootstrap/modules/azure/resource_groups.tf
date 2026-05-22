resource "azurerm_resource_group" "state" {
  name     = local.rg_state
  location = var.azure_location
  tags     = var.tags
}

resource "azurerm_resource_group" "identity" {
  name     = local.rg_identity
  location = var.azure_location
  tags     = var.tags
}

resource "azurerm_resource_group" "network" {
  count    = var.use_private_networking ? 1 : 0
  name     = local.rg_network
  location = var.azure_location
  tags     = var.tags
}

resource "azurerm_resource_group" "agents" {
  count    = var.use_self_hosted_runners ? 1 : 0
  name     = local.rg_agents
  location = var.azure_location
  tags     = var.tags
}
