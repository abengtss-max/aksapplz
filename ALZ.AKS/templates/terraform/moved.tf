# -----------------------------------------------------------------------------
# State migration - moved blocks
# The single-region stack was refactored into a reusable module instantiated
# per region. These moved blocks migrate the EXISTING flat state addresses into
# module.region["primary"] so existing deployments are NOT destroyed/recreated.
#
# ACR (module.acr) and the global load balancers stay at the root and need no
# move. Key Vault was a root module and moves under the region module.
# -----------------------------------------------------------------------------

# --- Networking ---
moved {
  from = azurerm_resource_group.main
  to   = module.region["primary"].azurerm_resource_group.main
}

moved {
  from = azurerm_route_table.aks
  to   = module.region["primary"].azurerm_route_table.aks
}

moved {
  from = azurerm_network_security_group.aks_system_nodes
  to   = module.region["primary"].azurerm_network_security_group.aks_system_nodes
}

moved {
  from = azurerm_network_security_group.aks_user_nodes
  to   = module.region["primary"].azurerm_network_security_group.aks_user_nodes
}

moved {
  from = azurerm_network_security_group.app_gateway
  to   = module.region["primary"].azurerm_network_security_group.app_gateway
}

moved {
  from = azurerm_network_security_group.private_endpoints
  to   = module.region["primary"].azurerm_network_security_group.private_endpoints
}

moved {
  from = module.spoke_vnet
  to   = module.region["primary"].module.spoke_vnet
}

moved {
  from = azurerm_virtual_network_peering.spoke_to_hub
  to   = module.region["primary"].azurerm_virtual_network_peering.spoke_to_hub
}

moved {
  from = azurerm_virtual_network_peering.hub_to_spoke
  to   = module.region["primary"].azurerm_virtual_network_peering.hub_to_spoke
}

# --- AKS ---
moved {
  from = azurerm_user_assigned_identity.aks
  to   = module.region["primary"].azurerm_user_assigned_identity.aks
}

moved {
  from = azurerm_role_assignment.aks_network_contributor
  to   = module.region["primary"].azurerm_role_assignment.aks_network_contributor
}

moved {
  from = azurerm_role_assignment.aks_acr_pull
  to   = module.region["primary"].azurerm_role_assignment.aks_acr_pull
}

moved {
  from = module.aks
  to   = module.region["primary"].module.aks
}

moved {
  from = azapi_resource.aks_backup_extension
  to   = module.region["primary"].azapi_resource.aks_backup_extension
}

# --- Application Gateway ---
moved {
  from = azurerm_public_ip.app_gateway
  to   = module.region["primary"].azurerm_public_ip.app_gateway
}

moved {
  from = azurerm_web_application_firewall_policy.main
  to   = module.region["primary"].azurerm_web_application_firewall_policy.main
}

moved {
  from = azurerm_application_gateway.main
  to   = module.region["primary"].azurerm_application_gateway.main
}

moved {
  from = azurerm_monitor_diagnostic_setting.app_gateway
  to   = module.region["primary"].azurerm_monitor_diagnostic_setting.app_gateway
}

# --- Monitoring ---
moved {
  from = module.log_analytics
  to   = module.region["primary"].module.log_analytics
}

moved {
  from = azurerm_monitor_workspace.main
  to   = module.region["primary"].azurerm_monitor_workspace.main
}

moved {
  from = azurerm_monitor_data_collection_endpoint.prometheus
  to   = module.region["primary"].azurerm_monitor_data_collection_endpoint.prometheus
}

moved {
  from = azurerm_monitor_data_collection_rule.prometheus
  to   = module.region["primary"].azurerm_monitor_data_collection_rule.prometheus
}

moved {
  from = azurerm_monitor_data_collection_rule_association.prometheus
  to   = module.region["primary"].azurerm_monitor_data_collection_rule_association.prometheus
}

moved {
  from = azurerm_monitor_data_collection_rule_association.prometheus_dce
  to   = module.region["primary"].azurerm_monitor_data_collection_rule_association.prometheus_dce
}

moved {
  from = azurerm_dashboard_grafana.main
  to   = module.region["primary"].azurerm_dashboard_grafana.main
}

moved {
  from = azurerm_role_assignment.grafana_admin
  to   = module.region["primary"].azurerm_role_assignment.grafana_admin
}

moved {
  from = azurerm_role_assignment.grafana_monitoring_reader
  to   = module.region["primary"].azurerm_role_assignment.grafana_monitoring_reader
}

moved {
  from = azurerm_role_assignment.grafana_monitor_data_reader
  to   = module.region["primary"].azurerm_role_assignment.grafana_monitor_data_reader
}

# --- Key Vault (was a root module) ---
moved {
  from = module.key_vault
  to   = module.region["primary"].module.key_vault
}
