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
  description = "The environment name (e.g., dev, staging, prod, standalone, production). Long form used in tags/labels."
  type        = string
  default     = "prod"
  validation {
    condition     = can(regex("^[a-z0-9]{1,16}$", var.environment))
    error_message = "Environment must be 1-16 lowercase alphanumeric characters."
  }
}

variable "environment_short" {
  description = "Short form of the environment name (1-6 lowercase alphanumeric chars) used in resource naming where Azure name limits are tight (Key Vault, Grafana, storage, DCE/DCR). Defaults to var.environment when empty — keep empty to preserve existing resource names; set explicitly when var.environment exceeds 6 chars."
  type        = string
  default     = ""
  validation {
    condition     = var.environment_short == "" || can(regex("^[a-z0-9]{1,6}$", var.environment_short))
    error_message = "environment_short must be empty or 1-6 lowercase alphanumeric characters."
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
    agc               = optional(string, "10.10.24.0/24")
    jumpbox           = optional(string, "10.10.25.0/27")
    bastion           = optional(string, "10.10.26.0/26")
  })
  default = {
    aks_system_nodes  = "10.10.0.0/24"  # 256 IPs  - System node pool (CriticalAddonsOnly)
    aks_user_nodes    = "10.10.16.0/22" # 1024 IPs - User/workload node pools
    aks_api_server    = "10.10.20.0/28" # 16 IPs   - API server VNet integration
    app_gateway       = "10.10.21.0/24" # 256 IPs  - App Gateway
    private_endpoints = "10.10.22.0/24" # 256 IPs  - Private endpoints
    ingress           = "10.10.23.0/24" # 256 IPs  - Ingress/load balancer
    agc               = "10.10.24.0/24" # 256 IPs  - App Gateway for Containers (ALB) delegated subnet
    jumpbox           = "10.10.25.0/27" # 32 IPs   - Management jumpbox VM (opt-in)
    bastion           = "10.10.26.0/26" # 64 IPs   - AzureBastionSubnet (opt-in; /26 minimum)
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
    os_sku          = optional(string, "Ubuntu")
    max_pods        = number
    min_count       = number
    max_count       = number
    node_count      = number
    max_surge       = string
    # Taints for the system (default) node pool. Defaults to the
    # CriticalAddonsOnly taint so the system pool is reserved for AKS-managed
    # add-ons (which tolerate it) and user workloads land on the user pool.
    # CriticalAddonsOnly=true:NoSchedule is the only taint Azure permits on the
    # default system pool. Set to [] to opt out.
    node_taints = optional(list(string), ["CriticalAddonsOnly=true:NoSchedule"])
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
    os_sku          = optional(string, "Ubuntu")
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

variable "enable_defender_for_containers_plan" {
  description = <<-EOT
    Enable the SUBSCRIPTION-WIDE Microsoft Defender for Containers plan
    (azurerm_security_center_subscription_pricing, tier Standard) plus its
    agentless discovery and registry vulnerability-assessment extensions. This
    is required for full Defender for Cloud coverage (agentless scanning,
    registry scanning) on top of the in-cluster security_monitoring agent that
    enable_defender turns on. NOTE: this changes Defender pricing for the WHOLE
    subscription and incurs cost (~per protected vCPU / per image scanned).
    Defaults to false so the accelerator never silently enables billing.
  EOT
  type        = bool
  default     = false
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

variable "enable_agc" {
  description = <<-EOT
    Enable Application Gateway for Containers (AGC). When true, Terraform
    provisions the dedicated delegated subnet (delegated to
    Microsoft.ServiceNetworking/trafficControllers) and its NSG in every
    region, ready for the in-cluster ALB Controller to create and manage the
    Application Gateway for Containers resource ("managed by ALB Controller"
    deployment model). Terraform does NOT create the trafficControllers
    resource and does NOT install the ALB Controller — install it yourself and
    point it at the agc_subnet_id output. Coexists with enable_app_gateway.
  EOT
  type        = bool
  default     = false
}

variable "enable_agic" {
  description = <<-EOT
    Enable the Application Gateway Ingress Controller (AGIC) AKS add-on. When
    true (and enable_app_gateway = true), the WAF_v2 Application Gateway is
    wired to AKS as an in-cluster ingress controller: the add-on is enabled on
    the cluster and the AGIC managed identity is granted Contributor on the
    Application Gateway and Reader on the resource group. Distinct from
    enable_agc (Application Gateway for Containers / ALB).
  EOT
  type        = bool
  default     = false
}

variable "enable_diagnostic_settings" {
  description = "Enable diagnostic settings for all resources."
  type        = bool
  default     = true
}

variable "ingress_controller" {
  description = <<-EOT
    Ingress controller the Application Gateway forwards to when it is used as the
    AKS ingress (i.e. NOT AGIC and NOT Application Gateway for Containers). One of:
      - "istio"  : the managed Istio internal ingress gateway - set up and wired
                   end-to-end for you (requires enable_istio_service_mesh = true
                   and istio_internal_ingress_gateway = true). The CD pipeline
                   discovers its internal load balancer IP and sets it on the App
                   Gateway backend pool (no hard-coded IP);
      - "manual" : baseline only - you bring and configure your own (open-source)
                   internal ingress controller and wire it into the backend pool.
    Only meaningful when enable_app_gateway = true and enable_agic = false.
  EOT
  type        = string
  default     = "manual"
  validation {
    condition     = contains(["istio", "manual"], var.ingress_controller)
    error_message = "ingress_controller must be one of: istio, manual."
  }
}

variable "appgw_tls_key_vault_secret_id" {
  description = "Unversioned Key Vault secret ID of a CUSTOMER-PROVIDED TLS certificate for the Application Gateway HTTPS:443 listener. When set, an HTTPS listener and an HTTP->HTTPS redirect are configured (mode 'keyvault', recommended for production); the gateway reads the certificate using the AKS user-assigned identity (already granted Key Vault Secrets User). Only the unversioned secret URL is passed to Terraform - never the certificate or its password. Leave empty to fall back to appgw_tls_mode."
  type        = string
  default     = ""
}

variable "appgw_tls_mode" {
  description = "Application Gateway edge TLS behaviour when appgw_tls_key_vault_secret_id is not set. 'keyvault' = customer-provided certificate (recommended for production). 'self_signed' = the accelerator generates a self-signed certificate INSIDE Key Vault (private key born and kept in Key Vault, never in the repo or Terraform state) for dev/test only. 'disabled' = explicit HTTP-only listener. Production environments hard-fail unless mode resolves to 'keyvault'."
  type        = string
  default     = "self_signed"
  validation {
    condition     = contains(["keyvault", "self_signed", "disabled"], var.appgw_tls_mode)
    error_message = "appgw_tls_mode must be one of: keyvault, self_signed, disabled."
  }
}

variable "appgw_https_only" {
  description = "When true the Application Gateway serves HTTPS only and does NOT publish an HTTP->HTTPS redirect (strict posture). When false (default) HTTP:80 permanently redirects to HTTPS. Only meaningful when TLS is enabled."
  type        = bool
  default     = false
}

variable "appgw_ssl_policy_name" {
  description = "Predefined Application Gateway SSL policy applied to the gateway. The default enforces a minimum of TLS 1.2 (PCI-DSS 4.0.1 Req 4.1 / Microsoft strong-crypto guidance). Override only with another predefined policy that keeps TLS 1.2+."
  type        = string
  default     = "AppGwSslPolicy20220101"
}

variable "appgw_self_signed_subject" {
  description = "Optional X.509 subject for the self-signed certificate generated in Key Vault when appgw_tls_mode = self_signed. Defaults to CN=<app gateway name>. Ignored for keyvault/disabled modes."
  type        = string
  default     = ""
}

variable "ingress_backend_ip" {
  description = "Optional private IP used to seed the Application Gateway backend pool. Normally left empty: the CD pipeline discovers the live internal ingress LB IP and updates the backend pool out of band (Terraform ignores changes to the backend pool addresses)."
  type        = string
  default     = ""
}

variable "ingress_health_probe_path" {
  description = "HTTP path the Application Gateway health probe requests against the ingress backend."
  type        = string
  default     = "/"
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

variable "cd_identity_principal_ids" {
  description = "Principal (object) IDs of the CD managed identities (plan + apply). Each is granted 'Azure Kubernetes Service RBAC Reader' on every region's cluster so the CD apply job's `az aks command invoke` (Istio ingress auto-wire) works under Azure RBAC + disabled local accounts. Populated by the bootstrap via terraform/cd-identities.auto.tfvars; empty falls back to the plan-time terraform identity."
  type        = list(string)
  default     = []
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

variable "auto_scaler_profile" {
  description = "Opt-in cluster-autoscaler profile tuning applied to every region. Leave null (default) to keep the native AKS cluster-autoscaler defaults - the accelerator does not impose an opinionated profile because it is cluster-wide and the right cost-vs-performance values depend on your workload. Set only the keys you want to override. See docs: Advanced > Cluster autoscaler tuning."
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
  default = null

  validation {
    condition     = var.auto_scaler_profile == null || try(var.auto_scaler_profile.expander, null) == null || contains(["least-waste", "most-pods", "priority", "random"], var.auto_scaler_profile.expander)
    error_message = "auto_scaler_profile.expander must be one of: least-waste, most-pods, priority, random."
  }
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
  description = "Enable the managed Azure Backup for AKS solution (vault, extension, Trusted Access, policy and backup instance)."
  type        = bool
  default     = false
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

# --- Compliance & Governance Options ---

variable "enable_cost_analysis" {
  description = "Enable cost analysis add-on for AKS (requires Standard or Premium SKU)."
  type        = bool
  default     = false
}

# --- Management access (Azure Bastion + hardened jumpbox VM) ---

variable "enable_management_jumpbox" {
  description = "Provision an opt-in Azure Bastion host and a hardened, no-public-IP Linux jumpbox VM for secure management access to a private AKS cluster and private endpoints. Default `false`. Intended for STANDALONE deployments — ALZ/corp platforms typically provide centralized Bastion/VPN in the connectivity hub, so leave this off there. When true it creates an AzureBastionSubnet + Bastion host and a management subnet + Ubuntu VM (Microsoft Entra ID SSH login, system-assigned identity, auto-shutdown, locked-down NSG, tooling preinstalled). Adds an Azure Bastion public IP (the only public IP)."
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

variable "enable_private_endpoints" {
  description = <<-EOT
    Provision private endpoints for Key Vault and ACR. Default `true` — aligned
    with Microsoft Well-Architected Framework and Cloud Adoption Framework
    guidance for AKS landing zones (data-plane traffic should stay on the
    Azure backbone; public endpoints should be off unless there is an explicit
    reason).

    In corp/hub topology private endpoints are always used and private DNS
    zones come from the hub. In standalone (no-hub) topology this toggle
    additionally creates the private-endpoints subnet, disables the public
    endpoint on Key Vault and ACR, and — when no external
    *_private_dns_zone_ids are supplied — creates and links the
    `privatelink.vaultcore.azure.net` and `privatelink.azurecr.io` private DNS
    zones to the spoke VNet.

    IMPORTANT: with this on, ACR's public endpoint is UNREACHABLE. Any CI job
    that builds and pushes images must run on a runner with network line of
    sight to the registry (e.g. the self-hosted ACI runner in the VNet); a
    GitHub-hosted runner can no longer push. Key Vault and ACR control-plane
    (Terraform) operations are unaffected. Set to `false` to keep public
    endpoints (with deny-by-default ACLs and AcrPull RBAC) if you truly need
    GitHub-hosted runners to push images.
  EOT
  type        = bool
  default     = true
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
  description = "Grafana major version. Azure Managed Grafana Standard SKU requires 12 (v11 was retired); valid value: 12."
  type        = string
  default     = "12"
}

variable "grafana_zone_redundancy" {
  description = "Enable zone redundancy for Grafana."
  type        = bool
  default     = false
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
  description = "Entra ID group object ID for Grafana admin access."
  type        = string
}

variable "grafana_subscription_monitoring_reader" {
  description = "Grant the Managed Grafana identity the read-only Monitoring Reader role at SUBSCRIPTION scope so the built-in dashboards that query subscription-level data populate (Microsoft Defender for Cloud alerts, cross-subscription Azure Monitor views). Without it those dashboards show zero/empty because Azure Resource Graph is RBAC-filtered and the identity only has resource-group scope. Read-only; set false for strict least-privilege (AKS/Prometheus/Log Analytics dashboards still work)."
  type        = bool
  default     = true
}
