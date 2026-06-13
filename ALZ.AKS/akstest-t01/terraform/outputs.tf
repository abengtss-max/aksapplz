# -----------------------------------------------------------------------------
# Outputs - AKS Application Landing Zone
# Primary-region scalars are preserved for backward compatibility; per-region
# maps and global endpoints are added for multi-region deployments.
# -----------------------------------------------------------------------------

# --- Primary region (backward-compatible scalars) ---
output "resource_group_name" {
  description = "The name of the primary region's resource group."
  value       = module.region["primary"].resource_group_name
}

output "resource_group_id" {
  description = "The ID of the primary region's resource group."
  value       = module.region["primary"].resource_group_id
}

output "vnet_id" {
  description = "The ID of the primary spoke VNet."
  value       = module.region["primary"].vnet_id
}

output "vnet_name" {
  description = "The name of the primary spoke VNet."
  value       = module.region["primary"].vnet_name
}

output "aks_cluster_id" {
  description = "The ID of the primary AKS cluster."
  value       = module.region["primary"].aks_cluster_id
}

output "aks_cluster_name" {
  description = "The name of the primary AKS cluster."
  value       = module.region["primary"].aks_cluster_name
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL of the primary AKS cluster."
  value       = module.region["primary"].aks_oidc_issuer_url
}

output "aks_kubelet_identity" {
  description = "The kubelet managed identity of the primary AKS cluster."
  value       = module.region["primary"].aks_kubelet_identity
}

output "aks_managed_identity_id" {
  description = "The ID of the primary AKS user-assigned managed identity."
  value       = module.region["primary"].aks_managed_identity_id
}

output "aks_managed_identity_client_id" {
  description = "The client ID of the primary AKS user-assigned managed identity."
  value       = module.region["primary"].aks_managed_identity_client_id
}

output "key_vault_id" {
  description = "The ID of the primary Key Vault."
  value       = module.region["primary"].key_vault_id
}

output "key_vault_uri" {
  description = "The URI of the primary Key Vault."
  value       = module.region["primary"].key_vault_uri
}

output "log_analytics_workspace_id" {
  description = "The ID of the primary Log Analytics workspace."
  value       = module.region["primary"].log_analytics_workspace_id
}

output "monitor_workspace_id" {
  description = "The ID of the primary Azure Monitor workspace (Prometheus)."
  value       = module.region["primary"].monitor_workspace_id
}

output "grafana_endpoint" {
  description = "The endpoint URL for the primary Managed Grafana."
  value       = module.region["primary"].grafana_endpoint
}

output "app_gateway_id" {
  description = "The ID of the primary Application Gateway."
  value       = module.region["primary"].app_gateway_id
}

output "app_gateway_public_ip" {
  description = "The public IP address of the primary Application Gateway."
  value       = module.region["primary"].app_gateway_public_ip_address
}

output "agc_subnet_id" {
  description = "The resource ID of the primary region's Application Gateway for Containers (ALB) delegated subnet. Null unless enable_agc is true. Pass this to the ALB Controller association."
  value       = module.region["primary"].agc_subnet_id
}

# --- Global (shared) ---
output "acr_id" {
  description = "The ID of the (global) Azure Container Registry."
  value       = module.acr.resource_id
}

output "acr_login_server" {
  description = "The login server URL for ACR."
  value       = module.acr.resource.login_server
}

# --- Per-region maps (multi-region) ---
output "regions" {
  description = "The list of deployed regions (keys: primary, secondary)."
  value       = keys(local.regions)
}

output "aks_cluster_ids" {
  description = "Map of region key to AKS cluster ID."
  value       = { for k, r in module.region : k => r.aks_cluster_id }
}

output "aks_cluster_names" {
  description = "Map of region key to AKS cluster name."
  value       = { for k, r in module.region : k => r.aks_cluster_name }
}

output "resource_group_names" {
  description = "Map of region key to resource group name."
  value       = { for k, r in module.region : k => r.resource_group_name }
}

output "app_gateway_public_ips" {
  description = "Map of region key to Application Gateway public IP address."
  value       = { for k, r in module.region : k => r.app_gateway_public_ip_address }
}

output "agc_subnet_ids" {
  description = "Map of region key to Application Gateway for Containers (ALB) delegated subnet ID. Values are null unless enable_agc is true."
  value       = { for k, r in module.region : k => r.agc_subnet_id }
}

# --- Global load balancer endpoints ---
output "global_lb_type" {
  description = "The active global load balancer type (none, front_door, traffic_manager)."
  value       = local.global_lb_type
}

output "front_door_endpoint_hostname" {
  description = "The Front Door endpoint hostname (when global_lb_type = front_door)."
  value       = local.use_front_door ? try(module.front_door[0].frontdoor_endpoints["primary_ep"].host_name, null) : null
}

output "traffic_manager_fqdn" {
  description = "The Traffic Manager profile FQDN (when global_lb_type = traffic_manager)."
  value       = local.use_traffic_mgr ? try(module.traffic_manager[0].fqdn, null) : null
}

output "fleet_manager_id" {
  description = "The Azure Kubernetes Fleet Manager ID (when enabled)."
  value       = local.enable_fleet ? azurerm_kubernetes_fleet_manager.main[0].id : null
}
