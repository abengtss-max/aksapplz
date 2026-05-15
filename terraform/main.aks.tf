# -----------------------------------------------------------------------------
# AKS Cluster - Using Azure Verified Module
# Best Practices: Entra ID, Workload Identity, Defender, Autoscaling,
# System + User Node Pools, Private Cluster, API Server VNet Integration
# -----------------------------------------------------------------------------

# User-Assigned Managed Identity for AKS
resource "azurerm_user_assigned_identity" "aks" {
  name                = local.managed_identity_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

# Role assignment: AKS identity needs Network Contributor on the spoke VNet
resource "azurerm_role_assignment" "aks_network_contributor" {
  scope                = module.spoke_vnet.resource_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Role assignment: AKS identity needs AcrPull on ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = module.acr.resource_id
  role_definition_name = "AcrPull"
  principal_id         = module.aks.kubelet_identity[0].object_id
}

# AKS Cluster using Azure Verified Module
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.4"

  name                = local.aks_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  # Kubernetes version
  kubernetes_version = var.kubernetes_version

  # SKU
  sku_tier = var.aks_sku_tier # "Standard" for production, "Free" for dev

  # --------------------------------------------------------------------------
  # Identity - Use User-Assigned Managed Identity
  # --------------------------------------------------------------------------
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # --------------------------------------------------------------------------
  # Network Configuration - Azure CNI Overlay (best practice for large clusters)
  # --------------------------------------------------------------------------
  network_profile = {
    network_plugin      = var.network_plugin      # "azure"
    network_plugin_mode = var.network_plugin_mode  # "overlay"
    network_policy      = var.network_policy       # "calico" or "azure"
    outbound_type       = "userDefinedRouting"     # Route through hub firewall
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  # --------------------------------------------------------------------------
  # API Server - VNet Integration (private API server without full private cluster)
  # --------------------------------------------------------------------------
  api_server_access_profile = var.enable_api_server_vnet_integration ? {
    vnet_integration_enabled = true
    subnet_id                = module.spoke_vnet.subnets["aks_api_server"].resource_id
    authorized_ip_ranges     = var.api_server_authorized_ip_ranges
  } : null

  # Private cluster
  private_cluster_enabled             = var.private_cluster_enabled
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled
  private_dns_zone_id                 = var.private_dns_zone_id

  # --------------------------------------------------------------------------
  # Entra ID Integration (Azure AD RBAC)
  # --------------------------------------------------------------------------
  azure_active_directory_role_based_access_control = {
    azure_rbac_enabled     = true
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  # --------------------------------------------------------------------------
  # Workload Identity + OIDC Issuer
  # --------------------------------------------------------------------------
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # --------------------------------------------------------------------------
  # Microsoft Defender for Containers
  # --------------------------------------------------------------------------
  microsoft_defender = var.enable_defender ? {
    log_analytics_workspace_id = module.log_analytics.resource_id
  } : null

  # --------------------------------------------------------------------------
  # System Node Pool (default_node_pool)
  # Best Practice: Dedicated system pool, CriticalAddonsOnly taint
  # --------------------------------------------------------------------------
  default_node_pool = {
    name                        = "system"
    vm_size                     = var.system_node_pool.vm_size
    os_disk_size_gb             = var.system_node_pool.os_disk_size_gb
    os_disk_type                = var.system_node_pool.os_disk_type # "Ephemeral" for best performance
    vnet_subnet_id              = module.spoke_vnet.subnets["aks_nodes"].resource_id
    max_pods                    = var.system_node_pool.max_pods
    zones                       = var.availability_zones
    temporary_name_for_rotation = "systemtemp"
    only_critical_addons_enabled = true # Taint: CriticalAddonsOnly=true:NoSchedule

    auto_scaling_enabled = true
    min_count            = var.system_node_pool.min_count
    max_count            = var.system_node_pool.max_count
    node_count           = var.system_node_pool.node_count

    upgrade_settings = {
      max_surge = var.system_node_pool.max_surge
    }

    tags = local.default_tags
  }

  # --------------------------------------------------------------------------
  # User Node Pool(s)
  # Best Practice: Separate pool for workloads, autoscaling enabled
  # --------------------------------------------------------------------------
  node_pools = {
    user = {
      name                = "user"
      vm_size             = var.user_node_pool.vm_size
      os_disk_size_gb     = var.user_node_pool.os_disk_size_gb
      os_disk_type        = var.user_node_pool.os_disk_type
      vnet_subnet_id      = module.spoke_vnet.subnets["aks_nodes"].resource_id
      max_pods            = var.user_node_pool.max_pods
      zones               = var.availability_zones

      auto_scaling_enabled = true
      min_count            = var.user_node_pool.min_count
      max_count            = var.user_node_pool.max_count
      node_count           = var.user_node_pool.node_count

      mode = "User"

      upgrade_settings = {
        max_surge = var.user_node_pool.max_surge
      }

      node_labels = var.user_node_pool.node_labels
      tags        = local.default_tags
    }
  }

  # --------------------------------------------------------------------------
  # Auto-upgrade & Maintenance Window
  # --------------------------------------------------------------------------
  automatic_upgrade_channel = var.automatic_upgrade_channel # "patch"
  node_os_upgrade_channel   = var.node_os_upgrade_channel   # "NodeImage"

  maintenance_window_auto_upgrade = var.maintenance_window != null ? {
    frequency   = var.maintenance_window.frequency
    interval    = var.maintenance_window.interval
    duration    = var.maintenance_window.duration
    day_of_week = var.maintenance_window.day_of_week
    start_time  = var.maintenance_window.start_time
    utc_offset  = var.maintenance_window.utc_offset
  } : null

  # --------------------------------------------------------------------------
  # Monitoring - Azure Monitor / Container Insights
  # --------------------------------------------------------------------------
  monitor_metrics = var.enable_managed_prometheus ? {
    annotations_allowed = null
    labels_allowed      = null
  } : null

  oms_agent = {
    log_analytics_workspace_id      = module.log_analytics.resource_id
    msi_auth_for_monitoring_enabled = true
  }

  # --------------------------------------------------------------------------
  # Azure Policy Add-on
  # --------------------------------------------------------------------------
  azure_policy_enabled = true

  # --------------------------------------------------------------------------
  # KEDA (Kubernetes Event-Driven Autoscaler)
  # --------------------------------------------------------------------------
  workload_autoscaler_profile = {
    keda_enabled = var.enable_keda
  }

  # --------------------------------------------------------------------------
  # Image Cleaner
  # --------------------------------------------------------------------------
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  # --------------------------------------------------------------------------
  # Blob CSI Driver & Key Vault CSI Driver
  # --------------------------------------------------------------------------
  storage_profile = {
    blob_driver_enabled         = true
    disk_driver_enabled         = true
    file_driver_enabled         = true
    snapshot_controller_enabled = true
  }

  key_vault_secrets_provider = {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  depends_on = [
    azurerm_role_assignment.aks_network_contributor,
    module.spoke_vnet
  ]
}
