terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
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
  storage_use_azuread             = true

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
# Provider: Connectivity subscription (hub) — used for hub VNet peering.
# In standalone topology connectivity_subscription_id is empty; fall back to
# the workload subscription so the provider block stays valid. No resources
# reference this alias when standalone (peering module is conditional).
# -----------------------------------------------------------------------------
provider "azurerm" {
  alias                           = "connectivity"
  subscription_id                 = var.connectivity_subscription_id != "" ? var.connectivity_subscription_id : var.subscription_id
  resource_provider_registrations = "core"
  storage_use_azuread             = true
  features {}
}

provider "azuread" {}
