# =============================================================================
# AKS Application Landing Zone - Configuration
# =============================================================================
# This file contains all customizable settings for the AKS landing zone.
# Modify these values to match your environment and requirements.
# =============================================================================

# -----------------------------------------------------------------------------
# Core Settings
# -----------------------------------------------------------------------------
subscription_id              = "REPLACE_ME"  # Landing zone subscription ID
connectivity_subscription_id = "REPLACE_ME"  # Hub/connectivity subscription ID
tenant_id                    = "REPLACE_ME"  # Entra ID tenant ID
location                     = "swedencentral"
workload_name                = "app1"
environment                  = "prod"

tags = {
  "costCenter"   = "IT"
  "owner"        = "platform-team"
  "application"  = "aks-landing-zone"
}

# -----------------------------------------------------------------------------
# Networking - Spoke VNet
# -----------------------------------------------------------------------------
vnet_address_space = "10.10.0.0/16"

subnet_address_prefixes = {
  aks_nodes         = "10.10.0.0/22"   # 1024 IPs for AKS nodes
  aks_api_server    = "10.10.4.0/28"   # 16 IPs for API server VNet integration
  app_gateway       = "10.10.5.0/24"   # 256 IPs for Application Gateway
  private_endpoints = "10.10.6.0/24"   # 256 IPs for Private Endpoints
  ingress           = "10.10.7.0/24"   # 256 IPs for Ingress resources
}

# Hub VNet peering (from your ALZ deployment)
hub_vnet_resource_id         = "/subscriptions/CONNECTIVITY_SUB_ID/resourceGroups/rg-hub-swedencentral/providers/Microsoft.Network/virtualNetworks/hub-swedencentral"
hub_vnet_name                = "hub-swedencentral"
hub_vnet_resource_group_name = "rg-hub-swedencentral"
hub_firewall_private_ip      = "10.0.0.4"  # Your ALZ hub firewall IP
use_remote_gateways          = false        # Set to true if hub has VPN/ER gateways

# -----------------------------------------------------------------------------
# AKS Configuration
# -----------------------------------------------------------------------------
kubernetes_version = "1.30"
aks_sku_tier       = "Standard"  # Standard = 99.95% SLA with availability zones
availability_zones = ["1", "2", "3"]

# Network plugin
network_plugin      = "azure"
network_plugin_mode = "overlay"  # Overlay = separate pod CIDR, scales better
network_policy      = "calico"   # Calico for richer network policy support

# IP ranges
service_cidr   = "172.16.0.0/16"
dns_service_ip = "172.16.0.10"
pod_cidr       = "192.168.0.0/16"  # Used with overlay mode

# Private cluster
private_cluster_enabled             = true
private_cluster_public_fqdn_enabled = false
private_dns_zone_id                 = "system"

# API server VNet integration
enable_api_server_vnet_integration = true
api_server_authorized_ip_ranges    = []

# Entra ID admin groups
aks_admin_group_object_ids = ["REPLACE_ME"]  # Entra ID group for AKS admins

# Auto-upgrade
automatic_upgrade_channel = "patch"
node_os_upgrade_channel   = "NodeImage"

# Maintenance window
maintenance_window = {
  frequency   = "Weekly"
  interval    = 1
  duration    = 4
  day_of_week = "Sunday"
  start_time  = "02:00"
  utc_offset  = "+01:00"
}

# -----------------------------------------------------------------------------
# System Node Pool (CriticalAddonsOnly taint)
# Best Practice: Small dedicated pool for system components (CoreDNS, metrics-server)
# -----------------------------------------------------------------------------
system_node_pool = {
  vm_size         = "Standard_D4ds_v5"  # 4 vCPU, 16 GB RAM
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"         # Ephemeral disks = better IOPS, no cost
  max_pods        = 110
  min_count       = 2                   # Min 2 for HA across zones
  max_count       = 5
  node_count      = 2
  max_surge       = "33%"
}

# -----------------------------------------------------------------------------
# User Node Pool (application workloads)
# Best Practice: Autoscaling enabled, separate from system pool
# -----------------------------------------------------------------------------
user_node_pool = {
  vm_size         = "Standard_D4ds_v5"
  os_disk_size_gb = 128
  os_disk_type    = "Ephemeral"
  max_pods        = 110
  min_count       = 2
  max_count       = 20                  # Scale up to 20 nodes
  node_count      = 2
  max_surge       = "33%"
  node_labels = {
    "workload" = "user"
  }
}

# -----------------------------------------------------------------------------
# Features
# -----------------------------------------------------------------------------
enable_defender            = true   # Microsoft Defender for Containers
enable_keda                = true   # KEDA event-driven autoscaling
enable_managed_prometheus  = true   # Azure Managed Prometheus
enable_managed_grafana     = true   # Azure Managed Grafana
enable_app_gateway         = true   # Application Gateway with WAF v2
enable_diagnostic_settings = true   # Send diagnostics to Log Analytics

# -----------------------------------------------------------------------------
# Application Gateway with WAF v2
# -----------------------------------------------------------------------------
waf_mode                 = "Prevention"  # Prevention mode for production
app_gateway_min_capacity = 1
app_gateway_max_capacity = 10

# -----------------------------------------------------------------------------
# Azure Container Registry
# -----------------------------------------------------------------------------
acr_zone_redundancy_enabled = true
acr_retention_days          = 30
acr_private_dns_zone_ids    = []  # Set to existing ALZ private DNS zone IDs
keyvault_private_dns_zone_ids = []  # Set to existing ALZ private DNS zone IDs

# -----------------------------------------------------------------------------
# Monitoring
# -----------------------------------------------------------------------------
log_retention_days    = 90
grafana_sku           = "Standard"
grafana_zone_redundancy = true
grafana_public_access   = true
grafana_admin_group_object_id = "REPLACE_ME"  # Entra ID group for Grafana admins
