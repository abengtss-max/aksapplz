# -----------------------------------------------------------------------------
# Region module - Azure Key Vault (Azure Verified Module)
# AKS Secure Baseline: RBAC, Soft Delete, Purge Protection, public network
# access disabled, private endpoint REQUIRED.
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

  # Soft delete & purge protection
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # Network access:
  # - corp (hub present): public access OFF, private endpoint in the PE subnet.
  # - standalone (no hub / no PE subnet): public access ON with deny-by-default
  #   ACL + AzureServices bypass (AKS reaches the vault over the service network).
  public_network_access_enabled = local.is_corp ? false : true

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Private endpoint only when a private-endpoints subnet exists (corp topology).
  private_endpoints = local.is_corp ? {
    primary = {
      name                          = "pe-${local.key_vault_name}"
      subnet_resource_id            = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = var.keyvault_private_dns_zone_ids
      tags                          = local.default_tags
    }
  } : {}

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
