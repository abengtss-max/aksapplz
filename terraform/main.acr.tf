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

  # Private endpoint per region that has a private-endpoints subnet (corp).
  # The "primary" key + name are preserved so existing deployments are stable.
  private_endpoints = {
    for k, r in module.region : k => {
      name                          = k == "primary" ? "pe-${local.acr_name}" : "pe-${local.acr_name}-${k}"
      subnet_resource_id            = r.private_endpoints_subnet_id
      private_dns_zone_resource_ids = var.acr_private_dns_zone_ids
      tags                          = local.default_tags
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
