# =============================================================================
# Scenario: Single Region Baseline
# =============================================================================
# Standard AKS baseline architecture in a single Azure region.
# Follows the AKS Baseline Reference Architecture:
# https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks
#
# Features: Azure CNI Overlay, Calico network policy, Workload Identity,
# Defender, KEDA, Managed Prometheus + Grafana, ACR, Key Vault, App Gateway WAF
# =============================================================================

scenario = "single_region_baseline"

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
  aks_user_nodes    = "10.10.1.0/22"
  aks_api_server    = "10.10.5.0/28"
  app_gateway       = "10.10.6.0/24"
  private_endpoints = "10.10.7.0/24"
  ingress           = "10.10.8.0/24"
}

# --- AKS Configuration ---
aks_sku_tier       = "Standard"
availability_zones = ["1", "2", "3"]

# Private cluster (corp) or public API (online) — controlled by landing_zone_type
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
enable_vpa  = false
enable_node_auto_provisioning = false

# --- Networking Features ---
enable_app_gateway                        = true
enable_istio_service_mesh                 = false
enable_application_gateway_for_containers = false
enable_nginx_ingress                      = false

# --- Storage ---
enable_blob_csi_driver    = true
enable_disk_csi_driver    = true
enable_file_csi_driver    = true
enable_snapshot_controller = true

# --- GitOps ---
enable_flux = false
enable_dapr = false

# --- Compliance ---
enable_fips            = false
enable_cost_analysis   = false
enable_backup          = false

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
