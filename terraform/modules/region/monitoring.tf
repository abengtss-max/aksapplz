# -----------------------------------------------------------------------------
# Region module - Monitoring (Log Analytics, Managed Prometheus, Managed Grafana)
# -----------------------------------------------------------------------------

# Log Analytics Workspace (for Container Insights & diagnostics)
module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "~> 0.4"

  name                = local.log_analytics_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  log_analytics_workspace_retention_in_days = var.log_retention_days
  log_analytics_workspace_sku               = "PerGB2018"
}

# Azure Monitor Workspace (for Managed Prometheus)
resource "azurerm_monitor_workspace" "main" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = local.monitor_workspace_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  # Query (PromQL) public access is disabled when private link is in use; Grafana
  # reaches the workspace over a managed private endpoint (see
  # monitoring-privatelink.tf).
  public_network_access_enabled = local.monitor_private_link ? false : true
}

# Data Collection Endpoint for Prometheus
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = local.dce_prometheus_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "Linux"
  tags                = local.default_tags

  # Ingestion public access is disabled when private link is in use; the AKS
  # metrics agent reaches the DCE over the AMPLS private endpoint.
  public_network_access_enabled = local.monitor_private_link ? false : true
}

# Data Collection Rule for Prometheus metrics
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                        = local.dcr_prometheus_name
  resource_group_name         = azurerm_resource_group.main.name
  location                    = azurerm_resource_group.main.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
  kind                        = "Linux"
  tags                        = local.default_tags

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.main[0].id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }
}

# Associate DCR with AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                    = "dcra-prometheus-${local.name_prefix}"
  target_resource_id      = module.aks.resource_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus[0].id
}

# Associate DCE with AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "prometheus_dce" {
  count = var.enable_managed_prometheus ? 1 : 0

  target_resource_id          = module.aks.resource_id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
}

# -----------------------------------------------------------------------------
# Container Insights (ContainerLogV2 + inventory) data collection
#
# The AKS oms_agent add-on (aks.tf) enables the ama-logs agent with managed-
# identity auth, but the agent ships NOTHING unless a Container Insights data
# collection rule is associated with the cluster. Without this DCR the agent
# pulls an empty config and no Heartbeat / ContainerLogV2 rows reach the
# workspace. Ingestion is private via the AMPLS (the Log Analytics workspace is
# a scoped service - see monitoring-privatelink.tf); when Managed Prometheus is
# enabled the cluster's DCE association above also serves private config access.
# -----------------------------------------------------------------------------
resource "azurerm_monitor_data_collection_rule" "container_insights" {
  name                = local.dcr_container_insights_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  destinations {
    log_analytics {
      name                  = "ciworkspace"
      workspace_resource_id = module.log_analytics.resource_id
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["ciworkspace"]
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "1m"
          namespaceFilteringMode = "Off"
          namespaces             = ["kube-system", "gatekeeper-system", "azure-arc"]
          enableContainerLogV2   = true
        }
      })
    }
  }
}

# Associate the Container Insights DCR with the AKS cluster so ama-logs ships
# ContainerLogV2 + inventory / heartbeat to the Log Analytics workspace.
resource "azurerm_monitor_data_collection_rule_association" "container_insights" {
  name                    = "dcra-ci-${local.name_prefix}"
  target_resource_id      = module.aks.resource_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights.id
}

# -----------------------------------------------------------------------------
# Managed Grafana
# -----------------------------------------------------------------------------
resource "azurerm_dashboard_grafana" "main" {
  count = var.enable_managed_grafana ? 1 : 0

  name                = local.grafana_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  sku                           = var.grafana_sku # "Standard"
  zone_redundancy_enabled       = var.grafana_zone_redundancy
  public_network_access_enabled = local.grafana_public_access_effective
  api_key_enabled               = true
  grafana_major_version         = var.grafana_major_version

  identity {
    type = "SystemAssigned"
  }

  # Link to Azure Monitor workspace for Prometheus data source
  dynamic "azure_monitor_workspace_integrations" {
    for_each = var.enable_managed_prometheus ? [1] : []
    content {
      resource_id = azurerm_monitor_workspace.main[0].id
    }
  }
}

# Role assignment: Grafana Admin for the specified group
resource "azurerm_role_assignment" "grafana_admin" {
  count = var.enable_managed_grafana && var.grafana_admin_group_object_id != "" ? 1 : 0

  scope                = azurerm_dashboard_grafana.main[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = var.grafana_admin_group_object_id
}

# Role assignment: Grafana needs Monitoring Reader on the resource group
resource "azurerm_role_assignment" "grafana_monitoring_reader" {
  count = var.enable_managed_grafana ? 1 : 0

  scope                = azurerm_resource_group.main.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main[0].identity[0].principal_id
}

# Role assignment: Grafana needs Monitoring Data Reader on Azure Monitor workspace
resource "azurerm_role_assignment" "grafana_monitor_data_reader" {
  count = var.enable_managed_prometheus && var.enable_managed_grafana ? 1 : 0

  scope                = azurerm_monitor_workspace.main[0].id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.main[0].identity[0].principal_id
}

# Role assignment: Grafana needs Monitoring Reader at SUBSCRIPTION scope so the
# out-of-the-box dashboards that query subscription-level data populate — most
# notably the "Microsoft Defender for Cloud" dashboards (which read
# Microsoft.Security alerts via Azure Resource Graph) and the cross-subscription
# Azure Monitor dashboards. The RG-scoped Monitoring Reader above only covers
# this landing zone's resources, so without this grant those dashboards show
# zero/empty even when data exists — Azure Resource Graph is RBAC-filtered. This
# mirrors what Azure Managed Grafana's portal integration grants by default.
# Read-only; gated so strict least-privilege deployments can opt out (the AKS /
# Prometheus / Log Analytics dashboards keep working either way).
resource "azurerm_role_assignment" "grafana_subscription_monitoring_reader" {
  count = var.enable_managed_grafana && var.grafana_subscription_monitoring_reader ? 1 : 0

  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.main[0].identity[0].principal_id
}

# -----------------------------------------------------------------------------
# Managed Grafana private connectivity
# When private endpoints are in use (corp topology or standalone +
# enable_private_endpoints), public access is disabled by default and the
# workspace is reachable via a private endpoint in the PE subnet. The
# privatelink.grafana.azure.com zone is supplied from the hub (corp) or
# self-managed and linked to the spoke VNet for standalone deployments.
# -----------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "grafana" {
  count = var.enable_managed_grafana && local.manage_private_dns ? 1 : 0

  name                = "privatelink.grafana.azure.com"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "grafana" {
  count = var.enable_managed_grafana && local.manage_private_dns ? 1 : 0

  name                  = "pdnslink-grf-${local.name_prefix}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.grafana[0].name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

resource "azurerm_private_endpoint" "grafana" {
  count = var.enable_managed_grafana && local.use_private_endpoints ? 1 : 0

  name                = "pe-${local.grafana_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = module.spoke_vnet.subnets["private_endpoints"].resource_id
  tags                = local.default_tags

  private_service_connection {
    name                           = "psc-${local.grafana_name}"
    private_connection_resource_id = azurerm_dashboard_grafana.main[0].id
    subresource_names              = ["grafana"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(local.grafana_private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "grafana-dns-zone-group"
      private_dns_zone_ids = local.grafana_private_dns_zone_ids
    }
  }
}
