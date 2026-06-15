# -----------------------------------------------------------------------------
# Root - Local Values
# Global naming + per-region configuration map consumed by module.region.
# -----------------------------------------------------------------------------

locals {
  # Location shortcodes for naming
  location_short = {
    swedencentral = "swc"
    westeurope    = "weu"
    northeurope   = "neu"
    eastus        = "eus"
    eastus2       = "eu2"
  }

  loc_short           = lookup(local.location_short, var.location, substr(var.location, 0, 3))
  secondary_loc_short = var.secondary_location != "" ? lookup(local.location_short, var.secondary_location, substr(var.secondary_location, 0, 3)) : ""

  env_short = var.environment_short != "" ? var.environment_short : var.environment

  # Global naming
  name_prefix = "${var.workload_name}-${local.env_short}-${local.loc_short}"
  acr_name    = replace("acr${var.workload_name}${local.env_short}${local.loc_short}", "-", "")

  # ACR is created at the root and lives in the primary region's resource group.
  # We build its resource ID deterministically so the region module can grant
  # AcrPull without creating a dependency cycle (region -> acr -> region subnet).
  primary_resource_group_name = "rg-${local.name_prefix}"
  acr_resource_id             = "/subscriptions/${var.subscription_id}/resourceGroups/${local.primary_resource_group_name}/providers/Microsoft.ContainerRegistry/registries/${local.acr_name}"

  # Front Door / Traffic Manager / Fleet global resource names
  resource_group_name_global = "rg-${var.workload_name}-${local.env_short}-global"
  frontdoor_profile_name     = "afd-${var.workload_name}-${local.env_short}"
  frontdoor_endpoint_name    = "fde-${var.workload_name}-${local.env_short}"
  traffic_manager_name       = "tm-${var.workload_name}-${local.env_short}"
  # Traffic Manager DNS relative name must be globally unique.
  traffic_manager_dns_name = lower("${var.workload_name}-${local.env_short}-${substr(sha256("${var.subscription_id}-${var.workload_name}-${local.env_short}"), 0, 8)}")
  fleet_name               = "fleet-${var.workload_name}-${local.env_short}"

  # Tags
  default_tags = merge(var.tags, {
    workload    = var.workload_name
    environment = var.environment
    managed_by  = "terraform"
    project     = "aksapplz"
  })

  # DNS zone names for private endpoints
  private_dns_zones = {
    acr      = "privatelink.azurecr.io"
    keyvault = "privatelink.vaultcore.azure.net"
    aks      = "privatelink.${var.location}.azmk8s.io"
  }

  # Multi-region is enabled whenever a secondary location is supplied.
  is_multi_region = var.secondary_location != ""

  # Global load balancing selection (only meaningful when multi-region).
  global_lb_type   = local.is_multi_region ? var.global_lb_type : "none"
  use_front_door   = local.global_lb_type == "front_door"
  use_traffic_mgr  = local.global_lb_type == "traffic_manager"
  assign_dns_label = local.use_traffic_mgr

  # Fleet Manager is opt-in and only meaningful with more than one cluster.
  enable_fleet = local.is_multi_region && var.enable_fleet_manager

  # A global resource group is required for Front Door / Traffic Manager / Fleet.
  need_global_rg = local.use_front_door || local.use_traffic_mgr || local.enable_fleet

  # ACR uses a private endpoint whenever any region exposes a PE subnet (corp,
  # or standalone with enable_private_endpoints).
  # In a fully-standalone deployment with private endpoints off there is no PE
  # subnet, so ACR stays public.
  acr_has_private_endpoint = length([
    for k, r in module.region : k if r.private_endpoints_subnet_id != null
  ]) > 0

  # Self-manage the ACR privatelink.azurecr.io zone when private endpoints are
  # used but no external zone ids are supplied (standalone, no hub).
  acr_self_managed_dns = local.acr_has_private_endpoint && length(var.acr_private_dns_zone_ids) == 0

  # ---------------------------------------------------------------------------
  # Per-region configuration map. The primary region is always present; the
  # secondary is added only when var.secondary_location is set.
  # ---------------------------------------------------------------------------
  regions = merge(
    {
      primary = {
        location                     = var.location
        loc_short                    = local.loc_short
        vnet_address_space           = var.vnet_address_space
        subnet_address_prefixes      = var.subnet_address_prefixes
        hub_vnet_resource_id         = var.hub_vnet_resource_id
        hub_vnet_name                = var.hub_vnet_name
        hub_vnet_resource_group_name = var.hub_vnet_resource_group_name
        hub_firewall_private_ip      = var.hub_firewall_private_ip
        use_remote_gateways          = var.use_remote_gateways
        availability_zones           = var.availability_zones
        public_dns_label             = lower("${var.workload_name}${local.env_short}${local.loc_short}${substr(sha256("${var.subscription_id}-primary"), 0, 6)}")
      }
    },
    local.is_multi_region ? {
      secondary = {
        location                     = var.secondary_location
        loc_short                    = local.secondary_loc_short
        vnet_address_space           = var.secondary_vnet_address_space
        subnet_address_prefixes      = var.secondary_subnet_address_prefixes
        hub_vnet_resource_id         = var.secondary_hub_vnet_resource_id
        hub_vnet_name                = var.secondary_hub_vnet_name
        hub_vnet_resource_group_name = var.secondary_hub_vnet_resource_group_name
        hub_firewall_private_ip      = var.secondary_hub_firewall_private_ip
        use_remote_gateways          = var.use_remote_gateways
        availability_zones           = length(var.secondary_availability_zones) > 0 ? var.secondary_availability_zones : var.availability_zones
        public_dns_label             = lower("${var.workload_name}${local.env_short}${local.secondary_loc_short}${substr(sha256("${var.subscription_id}-secondary"), 0, 6)}")
      }
    } : {}
  )
}
