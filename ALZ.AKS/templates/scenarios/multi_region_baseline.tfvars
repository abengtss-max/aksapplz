# =============================================================================
# Scenario: Multi Region Baseline
# =============================================================================
# Multi-region AKS architecture with Azure Front Door, Fleet Manager,
# and geo-replicated container registry.
# Reference: https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster
#
# Additional features over single-region baseline:
# - Flux GitOps for consistent multi-cluster deployments
# - VPA for right-sizing across regions
# - Backup for cross-region recovery
# =============================================================================

scenario = "multi_region_baseline"

# --- Multi-Region ---
# Set secondary_location to enable a full second region (AKS + App Gateway +
# VNet + Key Vault) and ACR geo-replication. Leave empty for single-region.
secondary_location         = ""  # e.g. "westeurope"
enable_acr_geo_replication = true

# Global load balancer in front of both regional clusters (multi-region only):
#   none | front_door | traffic_manager
global_lb_type = "front_door"

# Azure Kubernetes Fleet Manager — auto-joins every regional cluster (multi-region only)
enable_fleet_manager = true

# Secondary-region networking (used only when secondary_location is set).
# Must not overlap the primary vnet_address_space below.
secondary_vnet_address_space = "10.20.0.0/16"
secondary_subnet_address_prefixes = {
  aks_system_nodes  = "10.20.0.0/24"
  aks_user_nodes    = "10.20.16.0/22"
  aks_api_server    = "10.20.5.0/28"
  app_gateway       = "10.20.6.0/24"
  private_endpoints = "10.20.7.0/24"
  ingress           = "10.20.8.0/24"
}

# Availability zones for the SECONDARY region's AKS node pools. Empty list
# inherits the primary's availability_zones. Set explicitly when the secondary
# region/SKU supports a different set (e.g. westeurope may offer only ["3"]).
secondary_availability_zones = []

# --- Networking ---
network_plugin      = "azure"
network_plugin_mode = "overlay"
network_policy      = "calico"
service_cidr        = "172.16.0.0/16"
dns_service_ip      = "172.16.0.10"
pod_cidr            = "192.168.0.0/16"

# --- Subnet address prefixes (system & user on separate subnets) ---
subnet_address_prefixes = {
  aks_system_nodes  = "10.10.0.0/24"
  aks_user_nodes    = "10.10.16.0/22"
  aks_api_server    = "10.10.5.0/28"
  app_gateway       = "10.10.6.0/24"
  private_endpoints = "10.10.7.0/24"
  ingress           = "10.10.8.0/24"
}

# --- AKS Configuration ---
aks_sku_tier       = "Standard"
availability_zones = ["1", "2", "3"]

private_cluster_enabled             = true
private_cluster_public_fqdn_enabled = false
private_dns_zone_id                 = "system"
enable_api_server_vnet_integration  = true

# Auto-upgrade
automatic_upgrade_channel = "patch"
node_os_upgrade_channel   = "NodeImage"

# --- Identity & Security ---
enable_workload_identity = true
enable_azure_rbac        = true
disable_local_accounts   = true
enable_image_cleaner     = true
enable_azure_policy      = true
enable_defender          = true

# --- Monitoring ---
enable_managed_prometheus  = true
enable_managed_grafana     = true
enable_diagnostic_settings = true

# --- Scaling ---
enable_keda = true
enable_vpa  = true  # Recommended for multi-region right-sizing
enable_node_auto_provisioning = false

# --- Networking Features ---
enable_app_gateway                        = true
enable_istio_service_mesh                 = false

# --- Storage ---
enable_blob_csi_driver    = true
enable_disk_csi_driver    = true
enable_file_csi_driver    = true
enable_snapshot_controller = true

# --- GitOps ---
enable_flux = true   # Recommended for consistent multi-cluster deployments
enable_dapr = false

# --- Compliance ---
enable_fips          = false
enable_cost_analysis = false
enable_backup        = true  # Recommended for cross-region recovery

# --- Node Pools ---
system_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 2
  max_count       = 5
  node_count      = 2
  max_surge       = "33%"
}

user_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 2
  max_count       = 20
  node_count      = 2
  max_surge       = "33%"
  node_labels = {
    "workload" = "user"
  }
}
