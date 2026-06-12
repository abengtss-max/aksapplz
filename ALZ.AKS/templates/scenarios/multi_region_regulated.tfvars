# =============================================================================
# Scenario: Multi Region Regulated (PCI-DSS 4.0.1)
# =============================================================================
# PCI-DSS compliant multi-region AKS with Azure Front Door,
# Fleet Manager, and geo-replicated resources.
# Reference: https://learn.microsoft.com/azure/aks/pci-network-segmentation
#
# Combines multi-region baseline with regulated hardening:
# - FIPS 140-2 compliant node OS
# - Azure network policy for PCI segmentation
# - Istio service mesh for mTLS
# - Flux GitOps for consistent regulated deployments
# - Backup for cross-region data protection
# =============================================================================

scenario = "multi_region_regulated"

# --- Multi-Region ---
# Set secondary_location to enable a full second region (AKS + App Gateway +
# VNet + Key Vault) and ACR geo-replication. Leave empty for single-region.
secondary_location         = ""  # e.g. "westeurope"
enable_acr_geo_replication = true

# Global load balancer in front of both regional clusters (multi-region only).
# Front Door Premium is recommended for regulated workloads (integrated WAF + TLS).
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

# --- Networking ---
network_plugin      = "azure"
network_plugin_mode = "overlay"
network_policy      = "azure"       # Azure NPM required for PCI-DSS network segmentation
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
aks_sku_tier       = "Premium"    # Premium required for regulated workloads
availability_zones = ["1", "2", "3"]

private_cluster_enabled             = true   # Mandatory for PCI-DSS
private_cluster_public_fqdn_enabled = false
private_dns_zone_id                 = "system"
enable_api_server_vnet_integration  = true

# Auto-upgrade
automatic_upgrade_channel = "patch"
node_os_upgrade_channel   = "SecurityPatch"  # Security patches only for regulated

# --- Identity & Security (hardened) ---
enable_workload_identity = true
enable_azure_rbac        = true
disable_local_accounts   = true   # Mandatory for PCI-DSS
enable_image_cleaner     = true
enable_azure_policy      = true   # Mandatory for PCI-DSS compliance
enable_defender          = true   # Mandatory for PCI-DSS

# --- Monitoring ---
enable_managed_prometheus  = true
enable_managed_grafana     = true
enable_diagnostic_settings = true

# --- Scaling ---
enable_keda = true
enable_vpa  = true   # Right-sizing across regions
enable_node_auto_provisioning = false

# --- Networking Features (hardened) ---
enable_app_gateway                        = true
enable_istio_service_mesh                 = true   # mTLS for PCI-DSS
istio_internal_ingress_gateway            = true
istio_external_ingress_gateway            = false

# --- Storage ---
enable_blob_csi_driver    = true
enable_disk_csi_driver    = true
enable_file_csi_driver    = true
enable_snapshot_controller = true

# --- GitOps ---
enable_flux = true   # Consistent regulated deployments across regions
enable_dapr = false

# --- Compliance (hardened) ---
enable_fips          = true    # FIPS 140-2 compliant node OS
enable_cost_analysis = true    # Compliance reporting
enable_backup        = true    # Cross-region data protection

# --- Node Pools (hardened) ---
system_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 3           # Higher minimum for regulated HA
  max_count       = 5
  node_count      = 3
  max_surge       = "33%"
}

user_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 3           # Higher minimum for regulated HA
  max_count       = 20
  node_count      = 3
  max_surge       = "33%"
  node_labels = {
    "workload"   = "user"
    "compliance" = "pci-dss"
  }
}
