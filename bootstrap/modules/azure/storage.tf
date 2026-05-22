module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "~> 0.7"

  name                            = var.resource_names["storage_account"]
  parent_id                       = azurerm_resource_group.state.id
  location                        = var.azure_location
  account_tier                    = "Standard"
  account_replication_type        = var.storage_account_replication_type
  shared_access_key_enabled       = false
  public_network_access_enabled   = var.use_private_networking ? false : true
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  network_rules = var.use_private_networking ? {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = var.allow_storage_access_from_my_ip ? [chomp(data.http.my_ip[0].response_body)] : []
  } : null

  # Tfstate container plus inline RBAC for the plan + apply MIs.
  containers = {
    tfstate = {
      name = var.resource_names["storage_container"]
      role_assignments = {
        plan = {
          role_definition_id_or_name = "Storage Blob Data Contributor"
          principal_id               = module.managed_identities["plan"].principal_id
        }
        apply = {
          role_definition_id_or_name = "Storage Blob Data Contributor"
          principal_id               = module.managed_identities["apply"].principal_id
        }
      }
    }
  }

  enable_telemetry = false
  tags             = var.tags
}
