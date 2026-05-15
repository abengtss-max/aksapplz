# -----------------------------------------------------------------------------
# Outputs - AKS Application Landing Zone
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "The name of the resource group."
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The ID of the resource group."
  value       = azurerm_resource_group.main.id
}

# Networking
output "vnet_id" {
  description = "The ID of the spoke VNet."
  value       = module.spoke_vnet.resource_id
}

output "vnet_name" {
  description = "The name of the spoke VNet."
  value       = module.spoke_vnet.name
}

output "aks_system_subnet_id" {
  description = "The ID of the AKS system node pool subnet."
  value       = module.spoke_vnet.subnets["aks_system_nodes"].resource_id
}

output "aks_user_subnet_id" {
  description = "The ID of the AKS user node pool subnet."
  value       = module.spoke_vnet.subnets["aks_user_nodes"].resource_id
}

# AKS
output "aks_cluster_id" {
  description = "The ID of the AKS cluster."
  value       = module.aks.resource_id
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster."
  value       = module.aks.name
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL for workload identity federation."
  value       = module.aks.oidc_issuer_profile_issuer_url
}

output "aks_kubelet_identity" {
  description = "The kubelet managed identity."
  value       = module.aks.kubelet_identity
}

# ACR
output "acr_id" {
  description = "The ID of the Azure Container Registry."
  value       = module.acr.resource_id
}

output "acr_login_server" {
  description = "The login server URL for ACR."
  value       = module.acr.resource.login_server
}

# Key Vault
output "key_vault_id" {
  description = "The ID of the Key Vault."
  value       = module.key_vault.resource_id
}

output "key_vault_uri" {
  description = "The URI of the Key Vault."
  value       = module.key_vault.uri
}

# Monitoring
output "log_analytics_workspace_id" {
  description = "The ID of the Log Analytics workspace."
  value       = module.log_analytics.resource_id
}

output "monitor_workspace_id" {
  description = "The ID of the Azure Monitor workspace (Prometheus)."
  value       = var.enable_managed_prometheus ? azurerm_monitor_workspace.main[0].id : null
}

output "grafana_endpoint" {
  description = "The endpoint URL for Managed Grafana."
  value       = var.enable_managed_grafana ? azurerm_dashboard_grafana.main[0].endpoint : null
}

# Application Gateway
output "app_gateway_id" {
  description = "The ID of the Application Gateway."
  value       = var.enable_app_gateway ? azurerm_application_gateway.main[0].id : null
}

output "app_gateway_public_ip" {
  description = "The public IP address of the Application Gateway."
  value       = var.enable_app_gateway ? azurerm_public_ip.app_gateway[0].ip_address : null
}

# Identity
output "aks_managed_identity_id" {
  description = "The ID of the AKS user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks.id
}

output "aks_managed_identity_client_id" {
  description = "The client ID of the AKS user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks.client_id
}
