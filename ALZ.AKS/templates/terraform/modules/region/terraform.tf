# -----------------------------------------------------------------------------
# Region module - provider requirements
# This module is instantiated once per Azure region. The root module passes the
# default azurerm provider and (for corp/spoke topologies) the azurerm.connectivity
# aliased provider used for the hub -> spoke peering.
# -----------------------------------------------------------------------------
terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.0"
      configuration_aliases = [azurerm.connectivity]
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
