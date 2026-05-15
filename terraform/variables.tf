# -----------------------------------------------------------------------------
# Variables - AKS Application Landing Zone
# -----------------------------------------------------------------------------

# =============================================================================
# Core Settings
# =============================================================================

variable "subscription_id" {
  description = "The Azure subscription ID for the AKS landing zone."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "The Azure subscription ID for the connectivity (hub) subscription."
  type        = string
}

variable "tenant_id" {
  description = "The Azure AD tenant ID."
  type        = string
}

variable "location" {
  description = "The Azure region for all resources."
  type        = string
  default     = "swedencentral"
}

variable "workload_name" {
  description = "The name of the workload (used in resource naming)."
  type        = string
  default     = "app1"
}

variable "environment" {
  description = "The environment name (e.g., dev, staging, prod)."
  type        = string
  default     = "prod"
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Networking
# =============================================================================

variable "vnet_address_space" {
  description = "The address space for the spoke VNet."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for each subnet."
  type = object({
    aks_nodes       = string
    aks_api_server  = string
    app_gateway     = string
    private_endpoints = string
    ingress         = string
  })
  default = {
    aks_nodes       = "10.10.0.0/22"   # 1024 IPs - AKS nodes
    aks_api_server  = "10.10.4.0/28"   # 16 IPs - API server VNet integration
    app_gateway     = "10.10.5.0/24"   # 256 IPs - App Gateway
    private_endpoints = "10.10.6.0/24" # 256 IPs - Private endpoints
    ingress         = "10.10.7.0/24"   # 256 IPs - Ingress/load balancer
  }
}

variable "hub_vnet_resource_id" {
  description = "The resource ID of the hub VNet to peer with."
  type        = string
}

variable "hub_vnet_name" {
  description = "The name of the hub VNet."
  type        = string
}

variable "hub_vnet_resource_group_name" {
  description = "The resource group name of the hub VNet."
  type        = string
}

variable "hub_firewall_private_ip" {
  description = "The private IP address of the hub Azure Firewall (for UDR)."
  type        = string
}

variable "use_remote_gateways" {
  description = "Whether to use the hub's VPN/ExpressRoute gateways."
  type        = bool
  default     = true
}

# =============================================================================
# AKS Configuration
# =============================================================================

variable "kubernetes_version" {
  description = "The version of Kubernetes for AKS."
  type        = string
  default     = "1.30"
}

variable "aks_sku_tier" {
  description = "The SKU tier for AKS. Use 'Standard' for production SLA."
  type        = string
  default     = "Standard"
  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "AKS SKU tier must be Free, Standard, or Premium."
  }
}

variable "availability_zones" {
  description = "Availability zones for AKS node pools and other resources."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "network_plugin" {
  description = "Network plugin to use (azure or kubenet)."
  type        = string
  default     = "azure"
}

variable "network_plugin_mode" {
  description = "Network plugin mode (overlay recommended for large clusters)."
  type        = string
  default     = "overlay"
}

variable "network_policy" {
  description = "Network policy provider (calico or azure)."
  type        = string
  default     = "calico"
}

variable "service_cidr" {
  description = "The CIDR range for Kubernetes services."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "The DNS service IP (must be within service_cidr)."
  type        = string
  default     = "172.16.0.10"
}

variable "pod_cidr" {
  description = "The CIDR range for pods (when using overlay mode)."
  type        = string
  default     = "192.168.0.0/16"
}

# Private cluster settings
variable "private_cluster_enabled" {
  description = "Whether to enable private cluster."
  type        = bool
  default     = true
}

variable "private_cluster_public_fqdn_enabled" {
  description = "Whether to enable public FQDN for private cluster."
  type        = bool
  default     = false
}

variable "private_dns_zone_id" {
  description = "The ID of the private DNS zone for the AKS API server. Use 'system' for AKS-managed."
  type        = string
  default     = "system"
}

# API Server VNet Integration
variable "enable_api_server_vnet_integration" {
  description = "Whether to enable API server VNet integration."
  type        = bool
  default     = true
}

variable "api_server_authorized_ip_ranges" {
  description = "Authorized IP ranges for the API server."
  type        = list(string)
  default     = []
}

# Entra ID
variable "aks_admin_group_object_ids" {
  description = "List of Entra ID group IDs for AKS admin access."
  type        = list(string)
}

# Auto-upgrade
variable "automatic_upgrade_channel" {
  description = "Auto-upgrade channel for AKS (none, patch, rapid, stable, node-image)."
  type        = string
  default     = "patch"
}

variable "node_os_upgrade_channel" {
  description = "Node OS auto-upgrade channel (None, Unmanaged, SecurityPatch, NodeImage)."
  type        = string
  default     = "NodeImage"
}

# Maintenance window
variable "maintenance_window" {
  description = "Maintenance window for auto-upgrades."
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = string
    start_time  = string
    utc_offset  = string
  })
  default = {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+01:00"
  }
}

# =============================================================================
# Node Pools
# =============================================================================

variable "system_node_pool" {
  description = "Configuration for the system node pool."
  type = object({
    vm_size         = string
    os_disk_size_gb = number
    os_disk_type    = string
    max_pods        = number
    min_count       = number
    max_count       = number
    node_count      = number
    max_surge        = string
  })
  default = {
    vm_size         = "Standard_D4ds_v5"
    os_disk_size_gb = 128
    os_disk_type    = "Ephemeral"
    max_pods        = 110
    min_count       = 2
    max_count       = 5
    node_count      = 2
    max_surge       = "33%"
  }
}

variable "user_node_pool" {
  description = "Configuration for the user (workload) node pool."
  type = object({
    vm_size         = string
    os_disk_size_gb = number
    os_disk_type    = string
    max_pods        = number
    min_count       = number
    max_count       = number
    node_count      = number
    max_surge       = string
    node_labels     = map(string)
  })
  default = {
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
}

# =============================================================================
# Features
# =============================================================================

variable "enable_defender" {
  description = "Enable Microsoft Defender for Containers."
  type        = bool
  default     = true
}

variable "enable_keda" {
  description = "Enable KEDA (Kubernetes Event-Driven Autoscaler)."
  type        = bool
  default     = true
}

variable "enable_managed_prometheus" {
  description = "Enable Managed Prometheus for AKS monitoring."
  type        = bool
  default     = true
}

variable "enable_managed_grafana" {
  description = "Enable Managed Grafana for dashboards."
  type        = bool
  default     = true
}

variable "enable_app_gateway" {
  description = "Enable Application Gateway with WAF v2."
  type        = bool
  default     = true
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources."
  type        = bool
  default     = true
}

# =============================================================================
# Application Gateway
# =============================================================================

variable "waf_mode" {
  description = "WAF mode: Detection or Prevention."
  type        = string
  default     = "Prevention"
}

variable "app_gateway_min_capacity" {
  description = "Minimum capacity for App Gateway autoscaling."
  type        = number
  default     = 1
}

variable "app_gateway_max_capacity" {
  description = "Maximum capacity for App Gateway autoscaling."
  type        = number
  default     = 10
}

# =============================================================================
# ACR
# =============================================================================

variable "acr_zone_redundancy_enabled" {
  description = "Enable zone redundancy for ACR."
  type        = bool
  default     = true
}

variable "acr_retention_days" {
  description = "Retention days for untagged manifests in ACR."
  type        = number
  default     = 30
}

variable "acr_private_dns_zone_ids" {
  description = "Private DNS zone IDs for ACR private endpoint."
  type        = list(string)
  default     = []
}

variable "keyvault_private_dns_zone_ids" {
  description = "Private DNS zone IDs for Key Vault private endpoint."
  type        = list(string)
  default     = []
}

# =============================================================================
# Monitoring
# =============================================================================

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days."
  type        = number
  default     = 90
}

variable "grafana_sku" {
  description = "Grafana SKU (Standard or Essential)."
  type        = string
  default     = "Standard"
}

variable "grafana_zone_redundancy" {
  description = "Enable zone redundancy for Grafana."
  type        = bool
  default     = true
}

variable "grafana_public_access" {
  description = "Enable public access for Grafana."
  type        = bool
  default     = true
}

variable "grafana_admin_group_object_id" {
  description = "Entra ID group object ID for Grafana admin access."
  type        = string
}
