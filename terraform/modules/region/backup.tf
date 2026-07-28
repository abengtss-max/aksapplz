# =============================================================================
# Azure Backup for AKS (managed solution)
# =============================================================================
# Microsoft-recommended managed backup for AKS clusters. Opt-in via
# var.enable_backup (default false). When enabled this provisions the complete,
# supported topology:
#
#   * a hardened blob storage account + container  (the backup datastore)
#   * a dedicated snapshot resource group          (persistent-volume snapshots)
#   * a Backup Vault (system-assigned identity)     (control plane + policy)
#   * the Backup Extension (native azurerm resource, AAD-based)
#   * AKS Trusted Access role binding (vault <-> cluster, least privilege)
#   * the role assignments the vault / extension / cluster identities require
#   * a default daily backup policy + a backup instance protecting the cluster
#
# Schedule/retention are Day-2 governance decisions owned by the workload team;
# sensible defaults are shipped and overridable (var.backup_retention_days).
#
# Prerequisite: when enable_backup = true the deploying identity must be able to
# create role assignments (Owner or User Access Administrator) on this
# subscription — the same capability already required by the cluster's other
# role assignments (AcrPull, Network Contributor, Grafana Admin).
# -----------------------------------------------------------------------------

data "azurerm_client_config" "current" {}

# --- Snapshot resource group (persistent-volume disk snapshots) ---------------
resource "azurerm_resource_group" "backup_snapshot" {
  count = var.enable_backup ? 1 : 0

  name     = "rg-${local.name_prefix}-snap"
  location = var.location
  tags     = local.default_tags
}

# --- Backup datastore: hardened storage account + private container ----------
resource "azurerm_storage_account" "backup" {
  count = var.enable_backup ? 1 : 0

  name                = local.backup_storage_account_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = var.backup_storage_replication_type

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  # Disable public network access when private endpoints are in use. The platform
  # (and MCAPS policy) mandate private connectivity, and once public access is
  # off VNet service endpoints are ignored, so the blob private endpoint created
  # below is the reachability path for the backup extension's in-cluster data
  # mover (and the VNet-injected deployer).
  public_network_access_enabled = local.use_private_endpoints ? false : true
  # AAD-only: the backup extension and vault authenticate with managed
  # identities (Storage Blob Data Contributor); shared keys are disabled.
  shared_access_key_enabled = false

  sas_policy {
    expiration_period = "01.00:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
    container_delete_retention_policy {
      days = 7
    }
  }

  # Default-deny network access. The backup extension reaches the account from
  # the AKS node subnets (service endpoint), and the Backup Vault reaches it as
  # a trusted Azure service / resource instance.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
    virtual_network_subnet_ids = [
      module.spoke_vnet.subnets["aks_system_nodes"].resource_id,
      module.spoke_vnet.subnets["aks_user_nodes"].resource_id,
    ]
    private_link_access {
      endpoint_resource_id = azurerm_data_protection_backup_vault.backup[0].id
      endpoint_tenant_id   = var.tenant_id
    }
  }

  # The node subnets are an in-place update to add the Microsoft.Storage service
  # endpoint; that update must complete before this account's network ACL is
  # validated, otherwise Azure returns SubnetsHaveNoServiceEndpointsConfigured.
  depends_on = [module.spoke_vnet]
}

# --- Private connectivity for the backup datastore ---------------------------
# When private endpoints are in use the storage account has public network
# access disabled (above), so the backup extension's in-cluster data mover (and
# the VNet-injected deployer) reach the blob service through a private endpoint
# in the spoke's private-endpoint subnet. Only one privatelink.blob.core.windows
# .net zone may exist per resource group, so the Azure Monitor (AMPLS) blob zone
# is reused when Managed Prometheus already manages it; otherwise this feature
# manages its own; in corp topology the zone id is supplied from the hub.
locals {
  backup_use_pe = var.enable_backup && local.use_private_endpoints

  backup_manage_blob_dns = local.backup_use_pe && local.manage_private_dns && !local.monitor_private_link

  backup_blob_dns_zone_id = (
    !local.backup_use_pe ? null :
    local.manage_private_dns ? (
      local.monitor_private_link
      ? try(azurerm_private_dns_zone.monitor["privatelink.blob.core.windows.net"].id, null)
      : try(azurerm_private_dns_zone.backup_blob[0].id, null)
    ) :
    try(one([for id in var.monitor_private_dns_zone_ids : id if length(regexall("privatelink[.]blob[.]core[.]windows[.]net$", id)) > 0]), null)
  )
}

resource "azurerm_private_dns_zone" "backup_blob" {
  count = local.backup_manage_blob_dns ? 1 : 0

  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.default_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "backup_blob" {
  count = local.backup_manage_blob_dns ? 1 : 0

  name                  = "pdnslink-bkp-blob-${local.name_prefix}"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.backup_blob[0].name
  virtual_network_id    = module.spoke_vnet.resource_id
  registration_enabled  = false
  tags                  = local.default_tags
}

resource "azurerm_private_endpoint" "backup_blob" {
  count = local.backup_use_pe ? 1 : 0

  name                = "pe-${local.backup_storage_account_name}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = module.spoke_vnet.subnets["private_endpoints"].resource_id
  tags                = local.default_tags

  private_service_connection {
    name                           = "psc-${local.backup_storage_account_name}"
    private_connection_resource_id = azurerm_storage_account.backup[0].id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = local.backup_blob_dns_zone_id != null ? [1] : []
    content {
      name                 = "blob-dns-zone-group"
      private_dns_zone_ids = [local.backup_blob_dns_zone_id]
    }
  }

  # Serialize this blob private endpoint against the Azure Monitor (AMPLS)
  # private endpoint. When Managed Prometheus is private this endpoint REUSES the
  # AMPLS-managed privatelink.blob.core.windows.net zone, so both endpoints write
  # records into the SAME zone. Deleting their private DNS zone groups
  # concurrently makes the Network resource provider return a transient 409
  # "AnotherOperationInProgress" that fails the whole destroy. This explicit
  # dependency tears this endpoint down BEFORE the AMPLS endpoint so the two
  # blob-zone operations never overlap. No-op when the AMPLS endpoint is absent
  # (count 0) - a depends_on on a zero-count resource is an empty dependency.
  depends_on = [azurerm_private_endpoint.monitor]
}

# The deploying identity creates the container over the AAD data plane (shared
# keys are disabled), so it needs a blob data role on the account first.
resource "azurerm_role_assignment" "backup_deployer_blob_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_storage_account.backup[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_container" "backup" {
  count = var.enable_backup ? 1 : 0

  name                  = "aks-cluster-backup"
  storage_account_id    = azurerm_storage_account.backup[0].id
  container_access_type = "private"

  # Wait for the deployer's blob data role + the network ACL to settle; data
  # plane auth is AAD-only and RBAC propagation must precede container create.
  # When private endpoints are in use the deployer reaches the blob service over
  # the private endpoint, so it (and its DNS link) must exist before this create.
  depends_on = [
    azurerm_role_assignment.backup_deployer_blob_contributor,
    azurerm_private_endpoint.backup_blob,
    azurerm_private_dns_zone_virtual_network_link.backup_blob,
  ]
}

# Blob service diagnostic logging (read/write/delete) to Log Analytics.
resource "azurerm_monitor_diagnostic_setting" "backup_blob" {
  count = var.enable_backup ? 1 : 0

  name                       = "diag-${local.backup_storage_account_name}-blob"
  target_resource_id         = "${azurerm_storage_account.backup[0].id}/blobServices/default"
  log_analytics_workspace_id = module.log_analytics.resource_id

  enabled_log {
    category = "StorageRead"
  }
  enabled_log {
    category = "StorageWrite"
  }
  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

# --- Backup Vault -------------------------------------------------------------
resource "azurerm_data_protection_backup_vault" "backup" {
  count = var.enable_backup ? 1 : 0

  name                = "bvault-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tags                = local.default_tags

  datastore_type = "VaultStore"
  redundancy     = var.backup_vault_redundancy
  # Soft delete defaults to "On" (14-day hold) which blocks vault/RG teardown.
  # The accelerator favours reproducible create/destroy; override for prod.
  soft_delete = var.backup_vault_soft_delete

  identity {
    type = "SystemAssigned"
  }
}

# --- Backup Extension (native, AAD-based) ------------------------------------
resource "azurerm_kubernetes_cluster_extension" "backup" {
  count = var.enable_backup ? 1 : 0

  name              = "azure-aks-backup"
  cluster_id        = module.aks.resource_id
  extension_type    = "Microsoft.DataProtection.Kubernetes"
  release_train     = "stable"
  release_namespace = "dataprotection-microsoft"

  configuration_settings = {
    "configuration.backupStorageLocation.bucket"                = azurerm_storage_container.backup[0].name
    "configuration.backupStorageLocation.config.resourceGroup"  = azurerm_resource_group.main.name
    "configuration.backupStorageLocation.config.storageAccount" = azurerm_storage_account.backup[0].name
    "configuration.backupStorageLocation.config.subscriptionId" = data.azurerm_client_config.current.subscription_id
    # Use Microsoft Entra ID (AAD) auth for the BackupStorageLocation via the
    # extension's user-assigned identity (granted Storage Blob Data Contributor).
    # Required because the backup storage account has shared_access_key_enabled =
    # false; without this the data mover falls back to listing storage keys and
    # the BackupStorageLocation "default" becomes unavailable (ProtectionError).
    "configuration.backupStorageLocation.config.useAAD" = "true"
    "credentials.tenantId"                              = var.tenant_id
  }
}

# --- Trusted Access: Backup Vault -> AKS cluster (least privilege) ------------
resource "azurerm_kubernetes_cluster_trusted_access_role_binding" "backup" {
  count = var.enable_backup ? 1 : 0

  kubernetes_cluster_id = module.aks.resource_id
  name                  = "backup-operator"
  roles                 = ["Microsoft.DataProtection/backupVaults/backup-operator"]
  source_resource_id    = azurerm_data_protection_backup_vault.backup[0].id
}

# --- Role assignments ---------------------------------------------------------
# Extension identity -> storage account (write cluster-resource backups to blob)
resource "azurerm_role_assignment" "backup_ext_storage_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_storage_account.backup[0].id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_kubernetes_cluster_extension.backup[0].aks_assigned_identity[0].principal_id
}

resource "azurerm_role_assignment" "backup_ext_blob_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_storage_account.backup[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster_extension.backup[0].aks_assigned_identity[0].principal_id
}

# Backup Vault identity -> Reader on the AKS cluster
resource "azurerm_role_assignment" "backup_vault_reader_cluster" {
  count = var.enable_backup ? 1 : 0

  scope                = module.aks.resource_id
  role_definition_name = "Reader"
  principal_id         = azurerm_data_protection_backup_vault.backup[0].identity[0].principal_id
}

# Backup Vault identity -> snapshot resource group (read + snapshot ops)
resource "azurerm_role_assignment" "backup_vault_reader_snap" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_resource_group.backup_snapshot[0].id
  role_definition_name = "Reader"
  principal_id         = azurerm_data_protection_backup_vault.backup[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "backup_vault_snapshot_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_resource_group.backup_snapshot[0].id
  role_definition_name = "Disk Snapshot Contributor"
  principal_id         = azurerm_data_protection_backup_vault.backup[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "backup_vault_disk_operator" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_resource_group.backup_snapshot[0].id
  role_definition_name = "Data Operator for Managed Disks"
  principal_id         = azurerm_data_protection_backup_vault.backup[0].identity[0].principal_id
}

resource "azurerm_role_assignment" "backup_vault_blob_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_storage_account.backup[0].id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_data_protection_backup_vault.backup[0].identity[0].principal_id
}

# AKS cluster identity -> Contributor on snapshot RG (store PV snapshots)
resource "azurerm_role_assignment" "backup_cluster_snap_contributor" {
  count = var.enable_backup ? 1 : 0

  scope                = azurerm_resource_group.backup_snapshot[0].id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Data-plane RBAC (Storage Blob Data Contributor) is eventually consistent and
# can take a few minutes to propagate to the storage account. Without this wait
# the backup instance creation races ahead and fails with
# UserErrorExtensionMSIMissingPermissionsOnBackupStorageLocation. Hold for a few
# minutes after the storage-scoped role assignments before creating the instance.
resource "time_sleep" "backup_rbac_propagation" {
  count = var.enable_backup ? 1 : 0

  create_duration = "180s"

  depends_on = [
    azurerm_role_assignment.backup_ext_storage_contributor,
    azurerm_role_assignment.backup_ext_blob_contributor,
    azurerm_role_assignment.backup_vault_blob_contributor,
  ]
}

# --- Backup policy (daily, configurable retention) ----------------------------
resource "azurerm_data_protection_backup_policy_kubernetes_cluster" "backup" {
  count = var.enable_backup ? 1 : 0

  name                = "bkpol-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  vault_name          = azurerm_data_protection_backup_vault.backup[0].name

  # Daily backup at 02:00 UTC.
  backup_repeating_time_intervals = ["R/2024-01-01T02:00:00+00:00/P1D"]

  default_retention_rule {
    life_cycle {
      duration        = "P${var.backup_retention_days}D"
      data_store_type = "OperationalStore"
    }
  }
}

# --- Backup instance (protects the cluster) -----------------------------------
resource "azurerm_data_protection_backup_instance_kubernetes_cluster" "backup" {
  count = var.enable_backup ? 1 : 0

  name                         = "bkinst-${local.name_prefix}"
  location                     = azurerm_resource_group.main.location
  vault_id                     = azurerm_data_protection_backup_vault.backup[0].id
  kubernetes_cluster_id        = module.aks.resource_id
  snapshot_resource_group_name = azurerm_resource_group.backup_snapshot[0].name
  backup_policy_id             = azurerm_data_protection_backup_policy_kubernetes_cluster.backup[0].id

  backup_datasource_parameters {
    cluster_scoped_resources_enabled = true
    volume_snapshot_enabled          = true
  }

  depends_on = [
    azurerm_kubernetes_cluster_trusted_access_role_binding.backup,
    azurerm_role_assignment.backup_ext_storage_contributor,
    azurerm_role_assignment.backup_ext_blob_contributor,
    azurerm_role_assignment.backup_vault_reader_cluster,
    azurerm_role_assignment.backup_vault_reader_snap,
    azurerm_role_assignment.backup_vault_snapshot_contributor,
    azurerm_role_assignment.backup_vault_disk_operator,
    azurerm_role_assignment.backup_vault_blob_contributor,
    azurerm_role_assignment.backup_cluster_snap_contributor,
    time_sleep.backup_rbac_propagation,
  ]
}
