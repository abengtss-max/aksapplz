# -----------------------------------------------------------------------------
# Monitoring - Log Analytics, Managed Prometheus, Managed Grafana
# Best Practices: Centralized monitoring, Azure Monitor workspace,
# Prometheus data collection rules, Grafana dashboards
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
}

# Data Collection Endpoint for Prometheus
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                = "dce-prometheus-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  kind                = "Linux"
  tags                = local.default_tags
}

# Data Collection Rule for Prometheus metrics
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  count = var.enable_managed_prometheus ? 1 : 0

  name                        = "dcr-prometheus-${local.name_prefix}"
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
# Managed Grafana - Using Azure Verified Module
# ----------------------------------------------------------------------------- 

resource "azurerm_dashboard_grafana" "main" {
  count = var.enable_managed_grafana ? 1 : 0

  name                = local.grafana_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  sku                           = var.grafana_sku # "Standard"
  zone_redundancy_enabled       = var.grafana_zone_redundancy
  public_network_access_enabled = var.grafana_public_access
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
  count = var.enable_managed_grafana ? 1 : 0

  scope                = azurerm_dashboard_grafana.main[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = var.grafana_admin_group_object_id
}

# Role assignment: Grafana needs Monitoring Reader on the resource group (least privilege)
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
