# -----------------------------------------------------------------------------
# Region module - outputs
# -----------------------------------------------------------------------------

output "location" {
  description = "The Azure region of this region stack."
  value       = var.location
}

output "resource_group_name" {
  description = "The name of the region's resource group."
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The ID of the region's resource group."
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

output "private_endpoints_subnet_id" {
  description = "The ID of the private endpoints subnet (null when private endpoints are not used)."
  value       = local.use_private_endpoints ? module.spoke_vnet.subnets["private_endpoints"].resource_id : null
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

output "aks_managed_identity_id" {
  description = "The ID of the AKS user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks.id
}

output "aks_managed_identity_client_id" {
  description = "The client ID of the AKS user-assigned managed identity."
  value       = azurerm_user_assigned_identity.aks.client_id
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

output "app_gateway_public_ip_id" {
  description = "The resource ID of the Application Gateway public IP (used as a Traffic Manager Azure endpoint)."
  value       = var.enable_app_gateway ? azurerm_public_ip.app_gateway[0].id : null
}

output "app_gateway_public_ip_address" {
  description = "The public IP address of the Application Gateway."
  value       = var.enable_app_gateway ? azurerm_public_ip.app_gateway[0].ip_address : null
}

output "app_gateway_public_ip_fqdn" {
  description = "The fully-qualified domain name of the Application Gateway public IP (used as a Front Door origin host). Null unless a DNS label was assigned."
  value       = var.enable_app_gateway ? azurerm_public_ip.app_gateway[0].fqdn : null
}

# Application Gateway for Containers (ALB)
output "agc_subnet_id" {
  description = "The resource ID of the Application Gateway for Containers (ALB) delegated subnet. Null unless enable_agc is true. Pass this to the in-cluster ALB Controller association."
  value       = var.enable_agc ? module.spoke_vnet.subnets["agc"].resource_id : null
}
