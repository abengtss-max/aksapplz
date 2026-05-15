# -----------------------------------------------------------------------------
# Variables - AKS Application Landing Zone
# -----------------------------------------------------------------------------

# =============================================================================
# Core Settings
# =============================================================================

variable "landing_zone_type" {
  description = <<-EOT
    The type of Azure Landing Zone subscription to deploy into:
    - "corp"   : Connected to hub VNet via peering, forced tunneling through 
                 firewall (UDR), private cluster, private endpoints. Platform 
                 team manages hub networking.
    - "online" : Internet-facing, no hub connectivity, public endpoints, 
                 AKS outbound via load balancer. No peering or UDR required.
  EOT
  type        = string
  default     = "corp"
  validation {
    condition     = contains(["corp", "online"], var.landing_zone_type)
    error_message = "landing_zone_type must be either 'corp' or 'online'."
  }
}

variable "subscription_id" {
  description = "The Azure subscription ID for the AKS landing zone."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "The Azure subscription ID for the connectivity (hub) subscription. Only required for 'corp' landing zones."
  type        = string
  default     = ""
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
  description = "The environment name (e.g., dev, staging, prod, or test identifier)."
  type        = string
  default     = "prod"
  validation {
    condition     = can(regex("^[a-z0-9]{1,8}$", var.environment))
    error_message = "Environment must be 1-8 lowercase alphanumeric characters."
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
  description = "Address prefixes for each subnet. System and user node pools are separated per AKS baseline best practices."
  type = object({
    aks_system_nodes  = string
    aks_user_nodes    = string
    aks_api_server    = string
    app_gateway       = string
    private_endpoints = string
    ingress           = string
  })
  default = {
    aks_system_nodes  = "10.10.0.0/24"  # 256 IPs  - System node pool (CriticalAddonsOnly)
    aks_user_nodes    = "10.10.16.0/22" # 1024 IPs - User/workload node pools
    aks_api_server    = "10.10.20.0/28" # 16 IPs   - API server VNet integration
    app_gateway       = "10.10.21.0/24" # 256 IPs  - App Gateway
    private_endpoints = "10.10.22.0/24" # 256 IPs  - Private endpoints
    ingress           = "10.10.23.0/24" # 256 IPs  - Ingress/load balancer
  }
}

variable "hub_vnet_resource_id" {
  description = "The resource ID of the hub VNet to peer with. Required for 'corp' landing zones."
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = "The name of the hub VNet. Required for 'corp' landing zones."
  type        = string
  default     = ""
}

variable "hub_vnet_resource_group_name" {
  description = "The resource group name of the hub VNet. Required for 'corp' landing zones."
  type        = string
  default     = ""
}

variable "hub_firewall_private_ip" {
  description = "The private IP address of the hub Azure Firewall (for UDR). Required for 'corp' landing zones."
  type        = string
  default     = ""
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
  default     = "1.33"
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
    max_surge       = string
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
# Scenario
# =============================================================================

variable "scenario" {
  description = <<-EOT
    The deployment scenario that pre-configures the architecture:
    - "single_region_baseline"   : Single-region AKS with corp/online connectivity
    - "multi_region_baseline"    : Multi-region AKS with Azure Front Door, Fleet Manager
    - "single_region_regulated"  : PCI-DSS compliant single-region AKS
    - "multi_region_regulated"   : PCI-DSS compliant multi-region AKS
  EOT
  type        = string
  default     = "single_region_baseline"
  validation {
    condition = contains([
      "single_region_baseline",
      "multi_region_baseline",
      "single_region_regulated",
      "multi_region_regulated"
    ], var.scenario)
    error_message = "scenario must be one of: single_region_baseline, multi_region_baseline, single_region_regulated, multi_region_regulated."
  }
}

variable "secondary_location" {
  description = "Secondary Azure region for multi-region scenarios (geo-replicated ACR, etc.)."
  type        = string
  default     = ""
}

variable "enable_acr_geo_replication" {
  description = "Enable geo-replication for ACR to the secondary location (multi-region scenarios)."
  type        = bool
  default     = false
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

# --- Identity & Security Options ---

variable "enable_workload_identity" {
  description = "Enable Workload Identity for pod-level Entra ID authentication."
  type        = bool
  default     = true
}

variable "enable_azure_rbac" {
  description = "Enable Azure RBAC for Kubernetes authorization (instead of native Kubernetes RBAC)."
  type        = bool
  default     = true
}

variable "disable_local_accounts" {
  description = "Disable local Kubernetes accounts (enforce Entra ID only)."
  type        = bool
  default     = true
}

variable "enable_image_cleaner" {
  description = "Enable automatic image cleaner to remove stale images from nodes."
  type        = bool
  default     = true
}

variable "image_cleaner_interval_hours" {
  description = "How often the image cleaner runs (in hours)."
  type        = number
  default     = 48
}

variable "enable_azure_policy" {
  description = "Enable Azure Policy add-on for AKS."
  type        = bool
  default     = true
}

# --- Networking Options ---

variable "enable_istio_service_mesh" {
  description = "Enable Istio-based service mesh add-on."
  type        = bool
  default     = false
}

variable "istio_internal_ingress_gateway" {
  description = "Enable Istio internal ingress gateway."
  type        = bool
  default     = false
}

variable "istio_external_ingress_gateway" {
  description = "Enable Istio external ingress gateway."
  type        = bool
  default     = false
}

variable "enable_application_gateway_for_containers" {
  description = "Enable Application Gateway for Containers (AGC) as advanced ingress."
  type        = bool
  default     = false
}

variable "enable_nginx_ingress" {
  description = "Enable the Web Application Routing (managed NGINX ingress) add-on."
  type        = bool
  default     = false
}

# --- Scaling & Compute Options ---

variable "enable_vpa" {
  description = "Enable Vertical Pod Autoscaler."
  type        = bool
  default     = false
}

variable "enable_node_auto_provisioning" {
  description = "Enable Node Auto Provisioning (NAP / Karpenter)."
  type        = bool
  default     = false
}

variable "enable_fips" {
  description = "Enable FIPS 140-2 compliant node OS."
  type        = bool
  default     = false
}

# --- GitOps & App Platform Options ---

variable "enable_flux" {
  description = "Enable Flux v2 GitOps extension for Kubernetes."
  type        = bool
  default     = false
}

variable "enable_dapr" {
  description = "Enable Dapr (Distributed Application Runtime) extension."
  type        = bool
  default     = false
}

# --- Storage Options ---

variable "enable_blob_csi_driver" {
  description = "Enable Azure Blob CSI driver."
  type        = bool
  default     = true
}

variable "enable_disk_csi_driver" {
  description = "Enable Azure Disk CSI driver."
  type        = bool
  default     = true
}

variable "enable_file_csi_driver" {
  description = "Enable Azure Files CSI driver."
  type        = bool
  default     = true
}

variable "enable_snapshot_controller" {
  description = "Enable volume snapshot controller."
  type        = bool
  default     = true
}

# --- Business Continuity Options ---

variable "enable_backup" {
  description = "Enable Azure Backup for AKS (via Backup extension)."
  type        = bool
  default     = false
}

# --- Compliance & Governance Options ---

variable "enable_cost_analysis" {
  description = "Enable cost analysis add-on for AKS (requires Standard or Premium SKU)."
  type        = bool
  default     = false
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

variable "grafana_major_version" {
  description = "Grafana major version. Valid values: 11, 12."
  type        = string
  default     = "11"
}

variable "grafana_zone_redundancy" {
  description = "Enable zone redundancy for Grafana."
  type        = bool
  default     = false
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
