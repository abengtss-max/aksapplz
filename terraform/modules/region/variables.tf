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
    agc               = optional(string, "10.10.24.0/24")
    jumpbox           = optional(string, "10.10.25.0/27")
    bastion           = optional(string, "10.10.26.0/26")
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
    os_sku          = optional(string, "Ubuntu")
    max_pods        = number
    min_count       = number
    max_count       = number
    node_count      = number
    max_surge       = string
    # Taints applied to the system (default) node pool. Defaults to the
    # CriticalAddonsOnly taint so the system pool is reserved for AKS-managed
    # add-ons (which tolerate it) and user workloads land on the user pool.
    # CriticalAddonsOnly=true:NoSchedule is the only taint Azure permits on the
    # default system pool. Set to [] to opt out.
    node_taints = optional(list(string), ["CriticalAddonsOnly=true:NoSchedule"])
  })
}

variable "user_node_pool" {
  type = object({
    vm_size         = string
    os_disk_size_gb = number
    os_disk_type    = string
    os_sku          = optional(string, "Ubuntu")
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

variable "enable_agc" {
  description = "Enable the Application Gateway for Containers (ALB) delegated subnet + NSG in this region. The in-cluster ALB Controller manages the trafficControllers resource; Terraform provisions infra only."
  type        = bool
  default     = false
}

variable "enable_agic" {
  description = "Enable the Application Gateway Ingress Controller (AGIC) AKS add-on, wiring the WAF_v2 Application Gateway as an in-cluster ingress backed by AKS. Requires enable_app_gateway = true. Distinct from enable_agc (Application Gateway for Containers / ALB)."
  type        = bool
  default     = false
}

variable "ingress_controller" {
  description = "Ingress controller that the Application Gateway forwards to when it is used as the AKS ingress (i.e. NOT AGIC and NOT Application Gateway for Containers). One of: 'istio' (managed Istio internal ingress gateway - set up and auto-wired) or 'manual' (baseline only; bring and wire your own open-source internal controller). Only meaningful when enable_app_gateway = true and enable_agic = false."
  type        = string
  default     = "manual"
  validation {
    condition     = contains(["istio", "manual"], var.ingress_controller)
    error_message = "ingress_controller must be one of: istio, manual."
  }
}

variable "appgw_tls_key_vault_secret_id" {
  description = "Unversioned Key Vault secret ID of the TLS certificate for the Application Gateway HTTPS:443 listener. When set, an HTTPS listener and an HTTP->HTTPS redirect are configured and the gateway reads the certificate using the AKS user-assigned identity (already granted Key Vault Secrets User). Leave empty to keep an HTTP-only listener."
  type        = string
  default     = ""
}

variable "ingress_backend_ip" {
  description = "Optional private IP of the internal ingress controller load balancer used to seed the Application Gateway backend pool. Normally left empty: the CD pipeline discovers the live internal LB IP after the controller is deployed and updates the backend pool out of band (Terraform ignores changes to the backend pool addresses)."
  type        = string
  default     = ""
}

variable "ingress_health_probe_path" {
  description = "HTTP path the Application Gateway health probe requests against the ingress backend."
  type        = string
  default     = "/"
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

variable "cd_identity_principal_ids" {
  description = "Principal (object) IDs of the CD managed identities (plan + apply) that run the pipeline. Each is granted 'Azure Kubernetes Service RBAC Reader' on the cluster so the CD apply job's `az aks command invoke` (Istio ingress auto-wire) can read in-cluster services under Azure RBAC + disabled local accounts. Populated automatically by the bootstrap; empty falls back to the current terraform identity."
  type        = list(string)
  default     = []
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

variable "auto_scaler_profile" {
  type = object({
    balance_similar_node_groups           = optional(string)
    daemonset_eviction_for_empty_nodes    = optional(bool)
    daemonset_eviction_for_occupied_nodes = optional(bool)
    expander                              = optional(string)
    ignore_daemonsets_utilization         = optional(bool)
    max_empty_bulk_delete                 = optional(string)
    max_graceful_termination_sec          = optional(string)
    max_node_provision_time               = optional(string)
    max_total_unready_percentage          = optional(string)
    new_pod_scale_up_delay                = optional(string)
    ok_total_unready_count                = optional(string)
    scale_down_delay_after_add            = optional(string)
    scale_down_delay_after_delete         = optional(string)
    scale_down_delay_after_failure        = optional(string)
    scale_down_unneeded_time              = optional(string)
    scale_down_unready_time               = optional(string)
    scale_down_utilization_threshold      = optional(string)
    scan_interval                         = optional(string)
    skip_nodes_with_local_storage         = optional(string)
    skip_nodes_with_system_pods           = optional(string)
  })
  default     = null
  description = "Opt-in cluster-autoscaler profile tuning. Leave null to keep native AKS defaults - the accelerator does not impose an opinionated profile because it is cluster-wide and the right cost-vs-performance values depend on the customer's workload. Set only the keys you want to override. See docs: Advanced > Cluster autoscaler tuning."

  validation {
    condition     = var.auto_scaler_profile == null || try(var.auto_scaler_profile.expander, null) == null || contains(["least-waste", "most-pods", "priority", "random"], var.auto_scaler_profile.expander)
    error_message = "auto_scaler_profile.expander must be one of: least-waste, most-pods, priority, random."
  }
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

variable "enable_flux" {
  type    = bool
  default = false
}

variable "enable_dapr" {
  type    = bool
  default = false
}

variable "enable_cost_analysis" {
  type    = bool
  default = false
}

variable "enable_backup" {
  type    = bool
  default = false
}

variable "backup_retention_days" {
  description = "Retention (days) for the default AKS backup policy operational datastore."
  type        = number
  default     = 30
}

variable "backup_storage_replication_type" {
  description = "Replication for the backup datastore storage account. ZRS/GZRS recommended; LRS only for non-critical."
  type        = string
  default     = "ZRS"
}

variable "backup_vault_redundancy" {
  description = "Backup Vault storage redundancy. LocallyRedundant or GeoRedundant (GeoRedundant cannot be changed later)."
  type        = string
  default     = "LocallyRedundant"
}

variable "backup_vault_soft_delete" {
  description = "Backup Vault soft delete. 'Off' allows reproducible teardown; set 'On' for production immutability."
  type        = string
  default     = "Off"
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

# --- Private endpoints ---
variable "enable_private_endpoints" {
  description = "Provision private endpoints for Key Vault and ACR. Default `true` — aligned with WAF/CAF guidance for AKS landing zones. In corp/hub topology private endpoints are always used and DNS zones come from the hub. In standalone (no-hub) topology this creates the private-endpoints subnet, disables public network access, and (when no external private DNS zone ids are supplied) creates + links `privatelink.vaultcore.azure.net` and `privatelink.azurecr.io` to the spoke VNet. Note: makes ACR public endpoint unreachable — image build/push must run on an in-VNet self-hosted runner. Set to `false` only if you must keep public endpoints (with deny-by-default ACLs) for GitHub-hosted runner image pushes."
  type        = bool
  default     = true
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
  default = "12"
}

variable "grafana_zone_redundancy" {
  type    = bool
  default = false
}

variable "grafana_public_access" {
  description = "Public network access for Managed Grafana. When null (default) it is derived from the private-endpoint posture: private (false) when private endpoints are in use, public (true) otherwise. Set true/false to override."
  type        = bool
  default     = null
}

variable "grafana_private_dns_zone_ids" {
  description = "Private DNS zone IDs (privatelink.grafana.azure.com) for the Grafana private endpoint, supplied from the hub in corp topology. Empty = self-manage the zone in standalone."
  type        = list(string)
  default     = []
}

variable "monitor_private_dns_zone_ids" {
  description = "Private DNS zone IDs for the Azure Monitor (AMPLS) private endpoint (privatelink.monitor.azure.com, .oms/.ods.opinsights.azure.com, .agentsvc.azure-automation.net, .blob.core.windows.net), supplied from the hub in corp topology. Empty = self-manage the zones in standalone."
  type        = list(string)
  default     = []
}

variable "grafana_admin_group_object_id" {
  type    = string
  default = ""
}

# --- Management access (Azure Bastion + hardened jumpbox VM) ---
variable "enable_management_jumpbox" {
  description = "Provision an opt-in Azure Bastion host and a hardened, no-public-IP Linux jumpbox VM for secure management access to a private AKS cluster and private endpoints. Default `false`. Intended for STANDALONE deployments — ALZ/corp platforms typically provide centralized Bastion/VPN in the hub, so leave this off there. When true it creates an AzureBastionSubnet + Bastion host and a management subnet + Ubuntu VM (Entra ID SSH login, system-assigned identity, auto-shutdown, locked-down NSG, tooling preinstalled). Adds an Azure Bastion public IP (the only public IP)."
  type        = bool
  default     = false
}

variable "jumpbox_vm_size" {
  description = "VM size for the management jumpbox. Only used when enable_management_jumpbox = true."
  type        = string
  default     = "Standard_B2s_v2"
}

variable "jumpbox_admin_username" {
  description = "Local admin username for the jumpbox VM. Login is via Microsoft Entra ID; password authentication is disabled. Only used when enable_management_jumpbox = true."
  type        = string
  default     = "azureuser"
}

variable "bastion_sku" {
  description = "Azure Bastion SKU. 'Standard' enables native client / tunneling; 'Basic' is browser-only. Only used when enable_management_jumpbox = true."
  type        = string
  default     = "Standard"
}

variable "jumpbox_auto_shutdown_time" {
  description = "Daily auto-shutdown time for the jumpbox VM in 24h HHmm format (e.g. '1900'). Only used when enable_management_jumpbox = true."
  type        = string
  default     = "1900"
}

variable "jumpbox_auto_shutdown_timezone" {
  description = "Windows time zone id for the jumpbox auto-shutdown schedule (e.g. 'W. Europe Standard Time'). Only used when enable_management_jumpbox = true."
  type        = string
  default     = "UTC"
}
