# -----------------------------------------------------------------------------
# Region module - AKS Cluster (Azure Verified Module)
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

# NOTE: The AcrPull grant for this region's kubelet identity is created at the
# root (main.acr.tf), scoped to the real ACR resource. Keeping it here would
# require the deterministic ACR id (to avoid a region<->acr cycle), which loses
# the dependency on the ACR resource and can race ahead of its creation.

# AKS Cluster using Azure Verified Module
module "aks" {
  source  = "Azure/avm-res-containerservice-managedcluster/azurerm"
  version = "~> 0.4.0"

  name      = local.aks_name
  parent_id = azurerm_resource_group.main.id
  location  = azurerm_resource_group.main.location
  tags      = local.default_tags

  # DNS prefix for the cluster
  dns_prefix = local.aks_name

  # Kubernetes version
  kubernetes_version = var.kubernetes_version

  # SKU
  sku = {
    name = "Base"
    tier = var.aks_sku_tier # "Standard" for production, "Free" for dev
  }

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
    network_plugin_mode = var.network_plugin_mode # "overlay"
    network_policy      = var.network_policy      # "calico" or "azure"
    outbound_type       = local.is_corp ? "userDefinedRouting" : "loadBalancer"
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    pod_cidr            = var.pod_cidr
  }

  # --------------------------------------------------------------------------
  # API Server - VNet Integration + Private Cluster settings
  # --------------------------------------------------------------------------
  api_server_access_profile = {
    enable_vnet_integration = var.enable_api_server_vnet_integration
    subnet_id               = var.enable_api_server_vnet_integration ? module.spoke_vnet.subnets["aks_api_server"].resource_id : null
    authorized_ip_ranges    = var.api_server_authorized_ip_ranges
    # Corp: private cluster with system-managed DNS zone
    # Online: public API server
    # Private cluster is honored independently of corp/online connectivity so a
    # standalone deployment can still run a private API server (paired with API
    # Server VNet Integration). Only the system-managed private DNS zone is
    # wired when the cluster is actually private.
    enable_private_cluster             = var.private_cluster_enabled
    enable_private_cluster_public_fqdn = var.private_cluster_enabled ? var.private_cluster_public_fqdn_enabled : false
    private_dns_zone                   = var.private_cluster_enabled ? var.private_dns_zone_id : null
  }

  # --------------------------------------------------------------------------
  # Entra ID Integration (Azure AD RBAC)
  # --------------------------------------------------------------------------
  aad_profile = {
    enable_azure_rbac      = var.enable_azure_rbac
    managed                = true
    tenant_id              = var.tenant_id
    admin_group_object_ids = var.aks_admin_group_object_ids
  }

  # Local accounts
  disable_local_accounts = var.disable_local_accounts

  # --------------------------------------------------------------------------
  # OIDC Issuer + Workload Identity + Defender + Image Cleaner
  # --------------------------------------------------------------------------
  oidc_issuer_profile = {
    enabled = true
  }

  security_profile = {
    workload_identity = {
      enabled = var.enable_workload_identity
    }
    defender = var.enable_defender ? {
      log_analytics_workspace_resource_id = module.log_analytics.resource_id
      security_monitoring = {
        enabled = true
      }
    } : null
    image_cleaner = {
      enabled        = var.enable_image_cleaner
      interval_hours = var.image_cleaner_interval_hours
    }
  }

  # --------------------------------------------------------------------------
  # System Node Pool (default_agent_pool)
  # --------------------------------------------------------------------------
  default_agent_pool = {
    name                = "system"
    vm_size             = var.system_node_pool.vm_size
    os_disk_size_gb     = var.system_node_pool.os_disk_size_gb
    os_disk_type        = var.system_node_pool.os_disk_type # "Ephemeral" for best performance
    os_sku              = var.system_node_pool.os_sku       # "Ubuntu", "AzureLinux", "Ubuntu2204", ...
    vnet_subnet_id      = module.spoke_vnet.subnets["aks_system_nodes"].resource_id
    max_pods            = var.system_node_pool.max_pods
    availability_zones  = var.availability_zones
    enable_auto_scaling = true
    min_count           = var.system_node_pool.min_count
    max_count           = var.system_node_pool.max_count
    count_of            = var.system_node_pool.node_count
    enable_fips         = var.enable_fips

    upgrade_settings = {
      max_surge = var.system_node_pool.max_surge
    }

    tags = local.default_tags
  }

  # --------------------------------------------------------------------------
  # User Node Pool(s)
  # --------------------------------------------------------------------------
  agent_pools = {
    user = {
      name                = "user"
      vm_size             = var.user_node_pool.vm_size
      os_disk_size_gb     = var.user_node_pool.os_disk_size_gb
      os_disk_type        = var.user_node_pool.os_disk_type
      os_sku              = var.user_node_pool.os_sku
      vnet_subnet_id      = module.spoke_vnet.subnets["aks_user_nodes"].resource_id
      max_pods            = var.user_node_pool.max_pods
      availability_zones  = var.availability_zones
      enable_auto_scaling = true
      min_count           = var.user_node_pool.min_count
      max_count           = var.user_node_pool.max_count
      count_of            = var.user_node_pool.node_count
      mode                = "User"
      enable_fips         = var.enable_fips

      upgrade_settings = {
        max_surge = var.user_node_pool.max_surge
      }

      node_labels = var.user_node_pool.node_labels
      tags        = local.default_tags
    }
  }

  # --------------------------------------------------------------------------
  # Auto-upgrade
  # --------------------------------------------------------------------------
  auto_upgrade_profile = {
    upgrade_channel         = var.automatic_upgrade_channel # "patch"
    node_os_upgrade_channel = var.node_os_upgrade_channel   # "NodeImage"
  }

  # --------------------------------------------------------------------------
  # Maintenance Configuration
  # --------------------------------------------------------------------------
  maintenanceconfiguration = {
    auto_upgrade = {
      name = "aksManagedAutoUpgradeSchedule"
      maintenance_window = {
        duration_hours = var.maintenance_window.duration
        schedule = {
          weekly = {
            day_of_week    = var.maintenance_window.day_of_week
            interval_weeks = var.maintenance_window.interval
          }
        }
        start_time = var.maintenance_window.start_time
        utc_offset = var.maintenance_window.utc_offset
      }
    }
  }

  # --------------------------------------------------------------------------
  # Monitoring - Azure Monitor / Container Insights
  # --------------------------------------------------------------------------
  azure_monitor_profile = var.enable_managed_prometheus ? {
    metrics = {
      enabled = true
    }
  } : null

  addon_profile_oms_agent = {
    enabled = true
    config = {
      log_analytics_workspace_resource_id = module.log_analytics.resource_id
      use_aad_auth                        = true
    }
  }

  # --------------------------------------------------------------------------
  # Azure Policy Add-on
  # --------------------------------------------------------------------------
  addon_profile_azure_policy = {
    enabled = var.enable_azure_policy
  }

  # --------------------------------------------------------------------------
  # Application Gateway Ingress Controller (AGIC) add-on
  # Wires the WAF_v2 Application Gateway as an in-cluster ingress backed by AKS.
  # Enabled only when both the App Gateway and AGIC toggles are on.
  # --------------------------------------------------------------------------
  addon_profile_ingress_application_gateway = var.enable_app_gateway && var.enable_agic ? {
    enabled = true
    config = {
      application_gateway_id = azurerm_application_gateway.main[0].id
    }
  } : null

  # --------------------------------------------------------------------------
  # Service Mesh (Istio)
  # --------------------------------------------------------------------------
  service_mesh_profile = var.enable_istio_service_mesh ? {
    mode = "Istio"
    istio = {
      components = {
        ingress_gateways = concat(
          var.istio_internal_ingress_gateway ? [{ enabled = true, mode = "Internal" }] : [],
          var.istio_external_ingress_gateway ? [{ enabled = true, mode = "External" }] : []
        )
      }
    }
  } : null

  # --------------------------------------------------------------------------
  # KEDA & VPA
  # --------------------------------------------------------------------------
  workload_auto_scaler_profile = {
    keda = {
      enabled = var.enable_keda
    }
    vertical_pod_autoscaler = {
      enabled = var.enable_vpa
    }
  }

  # --------------------------------------------------------------------------
  # Node Auto Provisioning (NAP / Karpenter)
  # --------------------------------------------------------------------------
  node_provisioning_profile = var.enable_node_auto_provisioning ? {
    mode = "Auto"
  } : null

  # --------------------------------------------------------------------------
  # Blob CSI Driver & Key Vault CSI Driver
  # --------------------------------------------------------------------------
  storage_profile = {
    blob_csi_driver = {
      enabled = var.enable_blob_csi_driver
    }
    disk_csi_driver = {
      enabled = var.enable_disk_csi_driver
    }
    file_csi_driver = {
      enabled = var.enable_file_csi_driver
    }
    snapshot_controller = {
      enabled = var.enable_snapshot_controller
    }
  }

  addon_profile_key_vault_secrets_provider = {
    enabled = true
    config = {
      enable_secret_rotation = true
      rotation_poll_interval = "2m"
    }
  }

  # --------------------------------------------------------------------------
  # Diagnostic Settings
  # --------------------------------------------------------------------------
  diagnostic_settings = var.enable_diagnostic_settings ? {
    to_log_analytics = {
      name                  = "diag-${local.aks_name}"
      workspace_resource_id = module.log_analytics.resource_id
    }
  } : {}

  depends_on = [
    azurerm_role_assignment.aks_network_contributor,
    module.spoke_vnet
  ]
}

# NOTE: Azure Backup for AKS (storage, vault, extension, Trusted Access, policy
# and backup instance) is implemented as the complete managed solution in
# backup.tf, opt-in via var.enable_backup.

# -----------------------------------------------------------------------------
# AGIC (Application Gateway Ingress Controller) identity role assignments
# When the AGIC add-on is enabled, AKS provisions a managed identity that the
# ingress controller uses to program the Application Gateway. That identity
# needs Contributor on the Application Gateway and Reader on the resource group.
# The identity is read back from the cluster once the add-on is enabled.
# -----------------------------------------------------------------------------
data "azurerm_kubernetes_cluster" "agic" {
  count = var.enable_app_gateway && var.enable_agic ? 1 : 0

  name                = module.aks.name
  resource_group_name = azurerm_resource_group.main.name

  depends_on = [module.aks]
}

resource "azurerm_role_assignment" "agic_appgw_contributor" {
  count = var.enable_app_gateway && var.enable_agic ? 1 : 0

  scope                = azurerm_application_gateway.main[0].id
  role_definition_name = "Contributor"
  principal_id         = data.azurerm_kubernetes_cluster.agic[0].ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}

resource "azurerm_role_assignment" "agic_rg_reader" {
  count = var.enable_app_gateway && var.enable_agic ? 1 : 0

  scope                = azurerm_resource_group.main.id
  role_definition_name = "Reader"
  principal_id         = data.azurerm_kubernetes_cluster.agic[0].ingress_application_gateway[0].ingress_application_gateway_identity[0].object_id
}
