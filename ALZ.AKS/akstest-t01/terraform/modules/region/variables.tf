# -----------------------------------------------------------------------------
# Region module - variables
# Mirrors the root variable set for everything that is region-scoped. The root
# module passes these through, overriding the region-specific ones (location,
# address space, subnets, hub settings) per region.
# -----------------------------------------------------------------------------

# --- Core ---
variable "tenant_id" {
  description = "The Azure AD tenant ID."
  type        = string
}

variable "location" {
  description = "The Azure region for this region's resources."
  type        = string
}

variable "workload_name" {
  description = "The name of the workload (used in resource naming)."
  type        = string
}

variable "environment" {
  description = "The environment name (long form, used in tags/labels)."
  type        = string
}

variable "environment_short" {
  description = "Short form of the environment name used where Azure name limits are tight."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = map(string)
  default     = {}
}

# --- Networking ---
variable "vnet_address_space" {
  description = "The address space for this region's spoke VNet."
  type        = string
}

variable "subnet_address_prefixes" {
  description = "Address prefixes for each subnet in this region."
  type = object({
    aks_system_nodes  = string
    aks_user_nodes    = string
    aks_api_server    = string
    app_gateway       = string
    private_endpoints = string
    ingress           = string
  })
}

variable "hub_vnet_resource_id" {
  description = "The resource ID of the hub VNet to peer with. Empty = standalone (no peering)."
  type        = string
  default     = ""
}

variable "hub_vnet_name" {
  description = "The name of the hub VNet. Required for corp topologies."
  type        = string
  default     = ""
}

variable "hub_vnet_resource_group_name" {
  description = "The resource group name of the hub VNet. Required for corp topologies."
  type        = string
  default     = ""
}

variable "hub_firewall_private_ip" {
  description = "The private IP address of the hub Azure Firewall (for UDR)."
  type        = string
  default     = ""
}

variable "use_remote_gateways" {
  description = "Whether to use the hub's VPN/ExpressRoute gateways."
  type        = bool
  default     = true
}

# --- AKS ---
variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "aks_sku_tier" {
  type    = string
  default = "Standard"
}

variable "availability_zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "network_plugin" {
  type    = string
  default = "azure"
}

variable "network_plugin_mode" {
  type    = string
  default = "overlay"
}

variable "network_policy" {
  type    = string
  default = "calico"
}

variable "service_cidr" {
  type    = string
  default = "172.16.0.0/16"
}

variable "dns_service_ip" {
  type    = string
  default = "172.16.0.10"
}

variable "pod_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "private_cluster_enabled" {
  type    = bool
  default = true
}

variable "private_cluster_public_fqdn_enabled" {
  type    = bool
  default = false
}

variable "private_dns_zone_id" {
  type    = string
  default = "system"
}

variable "enable_api_server_vnet_integration" {
  type    = bool
  default = true
}

variable "api_server_authorized_ip_ranges" {
  type    = list(string)
  default = []
}

variable "aks_admin_group_object_ids" {
  type = list(string)
}

variable "automatic_upgrade_channel" {
  type    = string
  default = "patch"
}

variable "node_os_upgrade_channel" {
  type    = string
  default = "NodeImage"
}

variable "maintenance_window" {
  type = object({
    frequency   = string
    interval    = number
    duration    = number
    day_of_week = string
    start_time  = string
    utc_offset  = string
  })
}

variable "system_node_pool" {
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
}

variable "user_node_pool" {
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
}

# --- Feature toggles ---
variable "enable_defender" {
  type    = bool
  default = true
}

variable "enable_keda" {
  type    = bool
  default = true
}

variable "enable_managed_prometheus" {
  type    = bool
  default = true
}

variable "enable_managed_grafana" {
  type    = bool
  default = true
}

variable "enable_app_gateway" {
  type    = bool
  default = true
}

variable "enable_diagnostic_settings" {
  type    = bool
  default = true
}

variable "enable_workload_identity" {
  type    = bool
  default = true
}

variable "enable_azure_rbac" {
  type    = bool
  default = true
}

variable "disable_local_accounts" {
  type    = bool
  default = true
}

variable "enable_image_cleaner" {
  type    = bool
  default = true
}

variable "image_cleaner_interval_hours" {
  type    = number
  default = 48
}

variable "enable_azure_policy" {
  type    = bool
  default = true
}

variable "enable_istio_service_mesh" {
  type    = bool
  default = false
}

variable "istio_internal_ingress_gateway" {
  type    = bool
  default = false
}

variable "istio_external_ingress_gateway" {
  type    = bool
  default = false
}

variable "enable_vpa" {
  type    = bool
  default = false
}

variable "enable_node_auto_provisioning" {
  type    = bool
  default = false
}

variable "enable_fips" {
  type    = bool
  default = false
}

variable "enable_blob_csi_driver" {
  type    = bool
  default = true
}

variable "enable_disk_csi_driver" {
  type    = bool
  default = true
}

variable "enable_file_csi_driver" {
  type    = bool
  default = true
}

variable "enable_snapshot_controller" {
  type    = bool
  default = true
}

variable "enable_backup" {
  type    = bool
  default = false
}

# --- App Gateway ---
variable "waf_mode" {
  type    = string
  default = "Prevention"
}

variable "app_gateway_min_capacity" {
  type    = number
  default = 1
}

variable "app_gateway_max_capacity" {
  type    = number
  default = 10
}

# Public DNS label on the App Gateway public IP. Required when the IP is used
# as a Traffic Manager Azure endpoint. Off by default to keep single-region
# public IPs unchanged.
variable "assign_public_dns_label" {
  type    = bool
  default = false
}

variable "public_dns_label" {
  type    = string
  default = ""
}

# --- Key Vault ---
variable "keyvault_private_dns_zone_ids" {
  type    = list(string)
  default = []
}

# --- Monitoring ---
variable "log_retention_days" {
  type    = number
  default = 90
}

variable "grafana_sku" {
  type    = string
  default = "Standard"
}

variable "grafana_major_version" {
  type    = string
  default = "11"
}

variable "grafana_zone_redundancy" {
  type    = bool
  default = false
}

variable "grafana_public_access" {
  type    = bool
  default = true
}

variable "grafana_admin_group_object_id" {
  type    = string
  default = ""
}
