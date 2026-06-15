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
  # - private endpoints used (corp, or standalone + enable_private_endpoints):
  #   public access OFF, private endpoint in the PE subnet.
  # - otherwise (standalone default): public access ON with deny-by-default
  #   ACL + AzureServices bypass (AKS reaches the vault over the service network).
  public_network_access_enabled = local.use_private_endpoints ? false : true

  network_acls = {
    default_action = "Deny"
    bypass         = "AzureServices"
  }

  # Private endpoint whenever private endpoints are used. The private DNS zone is
  # supplied from the hub (corp) or self-managed for standalone deployments.
  private_endpoints = local.use_private_endpoints ? {
    primary = {
      name               = "pe-${local.key_vault_name}"
      subnet_resource_id = module.spoke_vnet.subnets["private_endpoints"].resource_id
      private_dns_zone_resource_ids = local.manage_private_dns ? (
        [azurerm_private_dns_zone.keyvault[0].id]
      ) : var.keyvault_private_dns_zone_ids
      tags = local.default_tags
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

# -----------------------------------------------------------------------------
# Self-managed Key Vault private DNS (standalone + enable_private_endpoints).
# In corp topology the privatelink.vaultcore.azure.net zone lives in the hub and
# is passed in via var.keyvault_private_dns_zone_ids; here we create and link a
# zone to the spoke VNet so the cluster resolves the vault to its private IP.
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "keyvault" {
  count = local.manage_private_dns ? 1 : 0

  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  count = local.manage_private_dns ? 1 : 0

  name                  = "pdnslink-kv-${local.name_prefix}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault[0].name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}
