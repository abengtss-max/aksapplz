# -----------------------------------------------------------------------------
# Azure Container Registry - Using Azure Verified Module
# Best Practices: Premium SKU, Private Endpoint, Zone Redundancy
# -----------------------------------------------------------------------------

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.4"

  name                = local.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  sku = "Premium" # Required for private endpoints and zone redundancy

  # Zone redundancy
  zone_redundancy_enabled = var.acr_zone_redundancy_enabled

  # Disable public access when using private endpoints
  public_network_access_enabled = false

  # Network rule set
  network_rule_bypass_option = "AzureServices"

  # Private endpoint for ACR
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
  retention_policy_enabled = true
}

# -----------------------------------------------------------------------------
# Azure Key Vault - Using Azure Verified Module
# Best Practices: RBAC, Soft Delete, Purge Protection, Private Endpoint
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

  # RBAC authorization (best practice over access policies)
  enable_rbac_authorization = true

  # Soft delete & purge protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Network - Disable public access
  public_network_access_enabled = false

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Private endpoint
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
