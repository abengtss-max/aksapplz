# -----------------------------------------------------------------------------
# Root - Regional stack (one instance per region)
# The primary region is always deployed. A secondary region is deployed when
# var.secondary_location is set, giving a full multi-region topology with a
# second, fully-configured AKS cluster + App Gateway + VNet + Key Vault.
# -----------------------------------------------------------------------------
module "region" {
  source   = "./modules/region"
  for_each = local.regions

  providers = {
    azurerm              = azurerm
    azurerm.connectivity = azurerm.connectivity
  }

  # Core
  tenant_id         = var.tenant_id
  location          = each.value.location
  workload_name     = var.workload_name
  environment       = var.environment
  environment_short = var.environment_short
  tags              = var.tags

  # Per-region networking
  vnet_address_space           = each.value.vnet_address_space
  subnet_address_prefixes      = each.value.subnet_address_prefixes
  hub_vnet_resource_id         = each.value.hub_vnet_resource_id
  hub_vnet_name                = each.value.hub_vnet_name
  hub_vnet_resource_group_name = each.value.hub_vnet_resource_group_name
  hub_firewall_private_ip      = each.value.hub_firewall_private_ip
  use_remote_gateways          = each.value.use_remote_gateways

  # Public DNS label (required for Traffic Manager Azure endpoints)
  assign_public_dns_label = local.assign_dns_label
  public_dns_label        = each.value.public_dns_label

  # AKS
  kubernetes_version                  = var.kubernetes_version
  aks_sku_tier                        = var.aks_sku_tier
  availability_zones                  = each.value.availability_zones
  network_plugin                      = var.network_plugin
  network_plugin_mode                 = var.network_plugin_mode
  network_policy                      = var.network_policy
  service_cidr                        = var.service_cidr
  dns_service_ip                      = var.dns_service_ip
  pod_cidr                            = var.pod_cidr
  private_cluster_enabled             = var.private_cluster_enabled
  private_cluster_public_fqdn_enabled = var.private_cluster_public_fqdn_enabled
  private_dns_zone_id                 = var.private_dns_zone_id
  enable_api_server_vnet_integration  = var.enable_api_server_vnet_integration
  api_server_authorized_ip_ranges     = var.api_server_authorized_ip_ranges
  aks_admin_group_object_ids          = var.aks_admin_group_object_ids
  automatic_upgrade_channel           = var.automatic_upgrade_channel
  node_os_upgrade_channel             = var.node_os_upgrade_channel
  maintenance_window                  = var.maintenance_window
  system_node_pool                    = var.system_node_pool
  user_node_pool                      = var.user_node_pool

  # Feature toggles (shared across regions)
  enable_defender                = var.enable_defender
  enable_keda                    = var.enable_keda
  enable_managed_prometheus      = var.enable_managed_prometheus
  enable_managed_grafana         = var.enable_managed_grafana
  enable_app_gateway             = var.enable_app_gateway
  enable_agc                     = var.enable_agc
  enable_diagnostic_settings     = var.enable_diagnostic_settings
  enable_workload_identity       = var.enable_workload_identity
  enable_azure_rbac              = var.enable_azure_rbac
  disable_local_accounts         = var.disable_local_accounts
  enable_image_cleaner           = var.enable_image_cleaner
  image_cleaner_interval_hours   = var.image_cleaner_interval_hours
  enable_azure_policy            = var.enable_azure_policy
  enable_istio_service_mesh      = var.enable_istio_service_mesh
  istio_internal_ingress_gateway = var.istio_internal_ingress_gateway
  istio_external_ingress_gateway = var.istio_external_ingress_gateway
  enable_vpa                     = var.enable_vpa
  enable_node_auto_provisioning  = var.enable_node_auto_provisioning
  enable_fips                    = var.enable_fips
  enable_blob_csi_driver         = var.enable_blob_csi_driver
  enable_disk_csi_driver         = var.enable_disk_csi_driver
  enable_file_csi_driver         = var.enable_file_csi_driver
  enable_snapshot_controller     = var.enable_snapshot_controller
  enable_backup                  = var.enable_backup
  backup_retention_days           = var.backup_retention_days
  backup_storage_replication_type = var.backup_storage_replication_type
  backup_vault_redundancy         = var.backup_vault_redundancy
  backup_vault_soft_delete        = var.backup_vault_soft_delete

  # App Gateway
  waf_mode                 = var.waf_mode
  app_gateway_min_capacity = var.app_gateway_min_capacity
  app_gateway_max_capacity = var.app_gateway_max_capacity

  # Key Vault
  keyvault_private_dns_zone_ids = var.keyvault_private_dns_zone_ids

  # Monitoring
  log_retention_days            = var.log_retention_days
  grafana_sku                   = var.grafana_sku
  grafana_major_version         = var.grafana_major_version
  grafana_zone_redundancy       = var.grafana_zone_redundancy
  grafana_public_access         = var.grafana_public_access
  grafana_admin_group_object_id = var.grafana_admin_group_object_id
}
