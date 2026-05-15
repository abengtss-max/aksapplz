terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }

  backend "azurerm" {}
}

# -----------------------------------------------------------------------------
# Provider: Main subscription (landing zone)
# resource_provider_registrations = "core" — azurerm handles standard providers
# -----------------------------------------------------------------------------
provider "azurerm" {
  resource_provider_registrations = "core"
  subscription_id                 = var.subscription_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

# -----------------------------------------------------------------------------
# Provider: Connectivity subscription (hub) — only used for Corp peering
# -----------------------------------------------------------------------------
provider "azurerm" {
  alias                           = "connectivity"
  subscription_id                 = var.landing_zone_type == "corp" ? var.connectivity_subscription_id : var.subscription_id
  resource_provider_registrations = "core"
  features {}
}

provider "azuread" {}
