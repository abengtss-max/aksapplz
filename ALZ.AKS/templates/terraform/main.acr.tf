# -----------------------------------------------------------------------------
# Root - Azure Container Registry (global, shared across regions)
# Premium SKU, geo-replicated to the secondary region for multi-region
# scenarios. Lives in the primary region's resource group. A private endpoint
# is created in every region that has a private-endpoints subnet (corp).
# Ref: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster
# -----------------------------------------------------------------------------

module "acr" {
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.4"

  name                = local.acr_name
  resource_group_name = module.region["primary"].resource_group_name
  location            = module.region["primary"].location
  tags                = local.default_tags

  sku = "Premium" # Required for zone redundancy, geo-replication and private endpoints

  # Zone redundancy
  zone_redundancy_enabled = var.acr_zone_redundancy_enabled

  # Network access:
  # - corp (any region has a PE subnet): public access OFF, private endpoint(s).
  # - standalone (no PE subnet anywhere): public access ON (AKS pulls over the
  #   public endpoint); AcrPull RBAC still gates access.
  public_network_access_enabled = local.acr_has_private_endpoint ? false : true

  # Network rule set
  network_rule_bypass_option = "AzureServices"

  # Private endpoint per region that has a private-endpoints subnet (corp, or
  # standalone with enable_private_endpoints).
  # The "primary" key + name are preserved so existing deployments are stable.
  # The private DNS zone is supplied from the hub (corp) or self-managed for
  # standalone deployments (privatelink.azurecr.io created below).
  private_endpoints = {
    for k, r in module.region : k => {
      name               = k == "primary" ? "pe-${local.acr_name}" : "pe-${local.acr_name}-${k}"
      subnet_resource_id = r.private_endpoints_subnet_id
      private_dns_zone_resource_ids = local.acr_self_managed_dns ? (
        [azurerm_private_dns_zone.acr[0].id]
      ) : var.acr_private_dns_zone_ids
      tags = local.default_tags
    } if r.private_endpoints_subnet_id != null
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

# Role assignment: each region's AKS kubelet identity needs AcrPull on the
# shared (global) ACR. Granted here at the root (rather than inside the region
# module) so it depends on the real ACR resource and the region's cluster
# without re-introducing a region<->acr dependency cycle.
resource "azurerm_role_assignment" "aks_acr_pull" {
  for_each = module.region

  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = each.value.aks_kubelet_identity.objectId
}

# -----------------------------------------------------------------------------
# Self-managed ACR private DNS (standalone + enable_private_endpoints).
# ACR is global, so the privatelink.azurecr.io zone is created once (in the
# primary region's resource group) and linked to every region's spoke VNet so
# each cluster resolves the registry (and its regional data endpoints) to the
# private endpoint. In corp topology the zone lives in the hub and is supplied
# via var.acr_private_dns_zone_ids instead.
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "acr" {
  count = local.acr_self_managed_dns ? 1 : 0

  name                = "privatelink.azurecr.io"
  resource_group_name = module.region["primary"].resource_group_name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  for_each = local.acr_self_managed_dns ? module.region : {}

  name                  = "pdnslink-acr-${each.key}"
  resource_group_name   = module.region["primary"].resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.acr[0].name
  virtual_network_id    = each.value.vnet_id
  registration_enabled  = false
  tags                  = local.default_tags
}
