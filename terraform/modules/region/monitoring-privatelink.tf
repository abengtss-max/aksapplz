# -----------------------------------------------------------------------------
# Region module - Managed Prometheus private connectivity
# (Azure Monitor Private Link Scope / AMPLS)
#
# When private endpoints are in use (corp topology or standalone +
# enable_private_endpoints) and Managed Prometheus is enabled, the Azure Monitor
# workspace and its data collection endpoint are taken off the public internet:
#   - Ingestion (AKS ama-metrics -> DCE -> workspace) flows over a private
#     endpoint into an AMPLS. The Prometheus DCE and the Log Analytics workspace
#     are added to the AMPLS as scoped services and their public network access
#     is disabled.
#   - Query (Managed Grafana -> workspace PromQL) uses a Grafana managed private
#     endpoint to the workspace (created below), so the workspace query endpoint
#     can also have public network access disabled.
#
# The privatelink DNS zones are self-managed and linked to the spoke VNet in
# standalone, or supplied from the hub via monitor_private_dns_zone_ids in corp.
# -----------------------------------------------------------------------------

locals {
  monitor_private_link = local.use_private_endpoints && var.enable_managed_prometheus

  # Azure Monitor privatelink DNS zones reached through the AMPLS "azuremonitor"
  # private endpoint (shared + regional Azure Monitor endpoints).
  monitor_privatelink_zones = [
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.blob.core.windows.net",
  ]

  # DNS zone ids consumed by the AMPLS private endpoint: the self-managed zones
  # in standalone, or hub-supplied ids in corp topology.
  monitor_ampls_dns_zone_ids = local.manage_private_dns ? [for z in azurerm_private_dns_zone.monitor : z.id] : var.monitor_private_dns_zone_ids
}

# Azure Monitor Private Link Scope (AMPLS)
resource "azurerm_monitor_private_link_scope" "monitor" {
  count = local.monitor_private_link ? 1 : 0

  name                = "ampls-${local.name_prefix}"
  resource_group_name = local.rg_network.name
  tags                = local.default_tags

  # Open mode keeps the VNet able to reach Azure Monitor resources that are not
  # in this AMPLS. Per-resource public network access is disabled separately
  # below, which is what removes public exposure. PrivateOnly would affect every
  # network that shares this DNS and is left to the platform team.
  ingestion_access_mode = "Open"
  query_access_mode     = "Open"
}

# Add the Prometheus data collection endpoint to the AMPLS (ingestion path).
resource "azurerm_monitor_private_link_scoped_service" "dce" {
  count = local.monitor_private_link ? 1 : 0

  name                = "amplss-dce-${local.name_prefix}"
  resource_group_name = local.rg_network.name
  scope_name          = azurerm_monitor_private_link_scope.monitor[0].name
  linked_resource_id  = azurerm_monitor_data_collection_endpoint.prometheus[0].id
}

# Add the Log Analytics workspace to the AMPLS (Container Insights logs).
resource "azurerm_monitor_private_link_scoped_service" "law" {
  count = local.monitor_private_link ? 1 : 0

  name                = "amplss-law-${local.name_prefix}"
  resource_group_name = local.rg_network.name
  scope_name          = azurerm_monitor_private_link_scope.monitor[0].name
  linked_resource_id  = module.log_analytics.resource_id
}

# Self-managed Azure Monitor privatelink DNS zones (standalone only; corp uses
# hub-supplied zone ids via monitor_private_dns_zone_ids).
resource "azurerm_private_dns_zone" "monitor" {
  for_each = local.monitor_private_link && local.manage_private_dns ? toset(local.monitor_privatelink_zones) : toset([])

  name                = each.value
  resource_group_name = local.rg_network.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "monitor" {
  for_each = local.monitor_private_link && local.manage_private_dns ? toset(local.monitor_privatelink_zones) : toset([])

  name                  = "pdnslink-mon-${replace(each.value, ".", "-")}"
  resource_group_name   = local.rg_network.name
  private_dns_zone_name = azurerm_private_dns_zone.monitor[each.value].name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

# Private endpoint into the AMPLS (subresource "azuremonitor").
resource "azurerm_private_endpoint" "monitor" {
  count = local.monitor_private_link ? 1 : 0

  name                = "pe-ampls-${local.name_prefix}"
  resource_group_name = local.rg_network.name
  location            = local.rg_network.location
  subnet_id           = module.spoke_vnet.subnets["private_endpoints"].resource_id
  tags                = local.default_tags

  private_service_connection {
    name                           = "psc-ampls-${local.name_prefix}"
    private_connection_resource_id = azurerm_monitor_private_link_scope.monitor[0].id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(local.monitor_ampls_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "monitor-dns-zone-group"
      private_dns_zone_ids = local.monitor_ampls_dns_zone_ids
    }
  }
}

# Managed Grafana private query path: a Grafana managed private endpoint to the
# Azure Monitor workspace so Grafana can run PromQL against the workspace after
# its public query endpoint is disabled. Creating the managed private endpoint
# leaves the workspace-side connection in a PENDING state - unlike a standard
# azurerm_private_endpoint (is_manual_connection=false), the Grafana control
# plane does NOT auto-approve it - so the pending connection is approved in-band
# by azapi_update_resource.approve_grafana_amw_mpe below.
resource "azapi_resource" "grafana_amw_mpe" {
  count = local.monitor_private_link && var.enable_managed_grafana ? 1 : 0

  type = "Microsoft.Dashboard/grafana/managedPrivateEndpoints@2023-09-01"
  # Grafana managed private endpoint names are limited to 2-20 characters
  # (alphanumeric/dashes, begin with a letter, end with a letter or digit), so
  # the descriptive name_prefix cannot be used directly. Use a short, stable
  # hash suffix to stay within the limit while remaining deterministic.
  name      = "mpe-amw-${substr(md5(local.name_prefix), 0, 8)}"
  parent_id = azurerm_dashboard_grafana.main[0].id
  location  = azurerm_resource_group.main.location
  tags      = local.default_tags

  # The Grafana control plane serializes operations per workspace and returns a
  # transient 409 (ConflictInProcessing: "Operation conflict occurred for
  # workspace ... Please try again later") when this managed private endpoint is
  # created OR deleted while another Grafana operation is still settling - which
  # is common on teardown, where Grafana itself is being deleted at the same
  # time. Retry the operation until the workspace is free instead of failing the
  # whole apply/destroy.
  retry = {
    error_message_regex  = ["ConflictInProcessing", "Operation conflict occurred", "AnotherOperationInProgress", "Please try again later"]
    interval_seconds     = 15
    max_interval_seconds = 120
  }

  body = {
    properties = {
      privateLinkResourceId     = azurerm_monitor_workspace.main[0].id
      privateLinkResourceRegion = azurerm_resource_group.main.location
      groupIds                  = ["prometheusMetrics"]
      requestMessage            = "aksapplz managed Grafana to Azure Monitor workspace (Prometheus)"
    }
  }

  depends_on = [
    azurerm_monitor_workspace.main,
    azurerm_dashboard_grafana.main,
    azurerm_monitor_private_link_scoped_service.dce,
  ]
}

# The Grafana managed private endpoint above lands the workspace-side connection
# in a PENDING state. Grafana cannot run PromQL against the workspace (queries
# fail with "Access through public network is disabled for this resource") until
# the connection is approved. There is no is_manual_connection=false auto-approve
# equivalent for Grafana managed private endpoints, so approve it in-band: look
# up the pending connection on the workspace, then PATCH its state to Approved.
# This keeps dashboards working on first deploy with no manual portal step.
data "azapi_resource_list" "amw_pe_connections" {
  count = local.monitor_private_link && var.enable_managed_grafana ? 1 : 0

  type                   = "Microsoft.Monitor/accounts/privateEndpointConnections@2023-04-03"
  parent_id              = azurerm_monitor_workspace.main[0].id
  response_export_values = ["value"]

  depends_on = [azapi_resource.grafana_amw_mpe]
}

resource "azapi_update_resource" "approve_grafana_amw_mpe" {
  count = local.monitor_private_link && var.enable_managed_grafana ? 1 : 0

  type = "Microsoft.Monitor/accounts/privateEndpointConnections@2023-04-03"

  # Exactly one managed private endpoint (Grafana's) targets this workspace, so
  # the first (and only) connection is the one to approve. Re-applies are
  # idempotent: PATCHing an already-Approved connection is a no-op.
  resource_id = data.azapi_resource_list.amw_pe_connections[0].output.value[0].id

  body = {
    properties = {
      privateLinkServiceConnectionState = {
        status      = "Approved"
        description = "Auto-approved by Terraform: Grafana managed private endpoint to Azure Monitor workspace (Prometheus)."
      }
    }
  }

  depends_on = [azapi_resource.grafana_amw_mpe]
}

# Approving the workspace-side connection is necessary but not sufficient. The
# Grafana instance caches its managed-private-endpoint connection state, so until
# it re-syncs it keeps failing queries with "Connection not established through
# an attached Private Endpoint" even though the workspace side is Approved. The
# refreshManagedPrivateEndpoints action forces Grafana to pull the now-Approved
# state and establish the private link, transitioning the Grafana-side connection
# from Pending to Approved and allocating its private IP. This mirrors the manual
# `az grafana managed-private-endpoint refresh` step (POST to
# .../grafana/{name}/refreshManagedPrivateEndpoints, no request body).
resource "azapi_resource_action" "refresh_grafana_mpe" {
  count = local.monitor_private_link && var.enable_managed_grafana ? 1 : 0

  type        = "Microsoft.Dashboard/grafana@2023-09-01"
  resource_id = azurerm_dashboard_grafana.main[0].id
  action      = "refreshManagedPrivateEndpoints"
  method      = "POST"

  # The Grafana control plane serializes operations per workspace and can return
  # a transient 409 while another operation on the same Grafana is still
  # settling; retry until it is free instead of failing the apply.
  retry = {
    error_message_regex  = ["ConflictInProcessing", "Operation conflict occurred", "AnotherOperationInProgress", "Please try again later"]
    interval_seconds     = 15
    max_interval_seconds = 120
  }

  # Re-run the refresh whenever the managed private endpoint or its approval is
  # (re)created so the Grafana side is always re-synced to the latest state; the
  # action is a safe no-op when the connection is already established.
  lifecycle {
    replace_triggered_by = [
      azapi_resource.grafana_amw_mpe,
      azapi_update_resource.approve_grafana_amw_mpe,
    ]
  }

  depends_on = [azapi_update_resource.approve_grafana_amw_mpe]
}
