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
# resource_provider_registrations = "none" — we register explicitly below
# -----------------------------------------------------------------------------
provider "azurerm" {
  resource_provider_registrations = "none"
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
  resource_provider_registrations = "none"
  features {}
}

provider "azuread" {}

# -----------------------------------------------------------------------------
# Explicit Resource Provider Registration
# Never assume providers are registered — register exactly what we need
# -----------------------------------------------------------------------------
resource "azurerm_resource_provider_registration" "compute" {
  name = "Microsoft.ContainerService"
}

resource "azurerm_resource_provider_registration" "network" {
  name = "Microsoft.Network"
}

resource "azurerm_resource_provider_registration" "storage" {
  name = "Microsoft.Storage"
}

resource "azurerm_resource_provider_registration" "keyvault" {
  name = "Microsoft.KeyVault"
}

resource "azurerm_resource_provider_registration" "container_registry" {
  name = "Microsoft.ContainerRegistry"
}

resource "azurerm_resource_provider_registration" "operational_insights" {
  name = "Microsoft.OperationalInsights"
}

resource "azurerm_resource_provider_registration" "insights" {
  name = "microsoft.insights"
}

resource "azurerm_resource_provider_registration" "monitor" {
  name = "Microsoft.Monitor"
}

resource "azurerm_resource_provider_registration" "dashboard" {
  count = var.enable_managed_grafana ? 1 : 0
  name  = "Microsoft.Dashboard"
}

resource "azurerm_resource_provider_registration" "managed_identity" {
  name = "Microsoft.ManagedIdentity"
}

resource "azurerm_resource_provider_registration" "authorization" {
  name = "Microsoft.Authorization"
}

resource "azurerm_resource_provider_registration" "security" {
  count = var.enable_defender ? 1 : 0
  name  = "Microsoft.Security"
}

resource "azurerm_resource_provider_registration" "kubernetes_configuration" {
  count = var.enable_flux || var.enable_backup ? 1 : 0
  name  = "Microsoft.KubernetesConfiguration"
}

resource "azurerm_resource_provider_registration" "data_protection" {
  count = var.enable_backup ? 1 : 0
  name  = "Microsoft.DataProtection"
}
