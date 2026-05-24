# -----------------------------------------------------------------------------
# Azure Container Registry - Using Azure Verified Module
# AKS Secure Baseline: Premium SKU, public network access disabled, private
# endpoint REQUIRED. Applies to both Corp and Online — the baseline never
# exposes the registry on the public internet.
# Ref: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/secure-baseline-aks
# -----------------------------------------------------------------------------

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.4"

  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  sku = "Premium" # Required for zone redundancy and private endpoints

  # Zone redundancy
  zone_redundancy_enabled = var.acr_zone_redundancy_enabled

  # AKS Secure Baseline: public access always off, private endpoint always on.
  public_network_access_enabled = false

  # Network rule set
  network_rule_bypass_option = "AzureServices"

  # Private endpoint for ACR (always — AKS Secure Baseline)
  private_endpoints = {
    primary = {
      name                          = "pe-${local.acr_name}"
      subnet_resource_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = var.acr_private_dns_zone_ids
      tags                          = local.default_tags
    }
  }

  # Content trust (image signing)
  anonymous_pull_enabled = false

  # Retention policy for untagged manifests
  retention_policy_in_days = var.acr_retention_days

  # Geo-replication for multi-region scenarios
  georeplications = var.enable_acr_geo_replication && var.secondary_location != "" ? [
    {
      location                = var.secondary_location
      zone_redundancy_enabled = true
      tags                    = local.default_tags
    }
  ] : []
}

# -----------------------------------------------------------------------------
# Azure Key Vault - Using Azure Verified Module
# AKS Secure Baseline: RBAC, Soft Delete, Purge Protection, public network
# access disabled, private endpoint REQUIRED. Applies to both Corp and Online.
# Ref: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/secure-baseline-aks
# -----------------------------------------------------------------------------

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.9"

  name                = local.key_vault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = var.tenant_id
  tags                = local.default_tags

  # SKU
  sku_name = "standard"

  # RBAC authorization is enabled by default (legacy_access_policies_enabled = false)

  # Soft delete & purge protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # AKS Secure Baseline: public access always off, private endpoint always on.
  public_network_access_enabled = false

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Private endpoint (always — AKS Secure Baseline)
  private_endpoints = {
    primary = {
      name                          = "pe-${local.key_vault_name}"
      subnet_resource_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = var.keyvault_private_dns_zone_ids
      tags                          = local.default_tags
    }
  }

  # Role assignments - AKS managed identity gets Secrets User
  role_assignments = {
    aks_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = azurerm_user_assigned_identity.aks.principal_id
    }
  }

  # Diagnostic settings
  diagnostic_settings = var.enable_diagnostic_settings ? {
    to_log_analytics = {
      name                  = "diag-${local.key_vault_name}"
      workspace_resource_id = module.log_analytics.resource_id
    }
  } : {}
}
