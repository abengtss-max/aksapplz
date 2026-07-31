# -----------------------------------------------------------------------------
# Region module - KMS etcd encryption with a customer-managed Key Vault key (#20)
#
# AKS Secure Baseline: encrypt Kubernetes secrets in etcd with a customer-managed
# key (the KMS plugin backed by Azure Key Vault) so secrets at rest are protected
# with a key you control, rotate and audit.
#
# Opt-in via var.enable_kms_etcd_encryption (default false). The key is created in
# the region's private Key Vault. Creating/rotating the key requires the deploying
# identity to have Key Vault data-plane access, so it is granted "Key Vault Crypto
# Officer" while KMS is enabled; the AKS cluster identity is granted "Key Vault
# Crypto User" to use the key at runtime. For a private Key Vault the deployer must
# have data-plane network reachability (a VNet-injected self-hosted runner).
# -----------------------------------------------------------------------------

variable "enable_kms_etcd_encryption" {
  type    = bool
  default = false
}

locals {
  # Grant every CD identity supplied by the bootstrap (plan + apply) so the key
  # can be created in either job; fall back to the current (plan-time) identity
  # for standalone `terraform apply` runs where that list is not populated.
  deployer_kms_principal_ids = var.enable_kms_etcd_encryption ? toset(
    length(var.cd_identity_principal_ids) > 0
    ? var.cd_identity_principal_ids
    : [data.azurerm_client_config.current.object_id]
  ) : toset([])
}

# Deployer needs Crypto Officer to create and rotate the etcd KMS key.
resource "azurerm_role_assignment" "deployer_kms_crypto_officer" {
  for_each = local.deployer_kms_principal_ids

  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = each.value
}

# AKS cluster identity uses the key for etcd envelope encryption at runtime.
resource "azurerm_role_assignment" "aks_kms_crypto_user" {
  count = var.enable_kms_etcd_encryption ? 1 : 0

  scope                = module.key_vault.resource_id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# Dedicated customer-managed key for etcd secret encryption. A versionless key id
# is wired into the cluster so AKS follows key rotation automatically.
resource "azurerm_key_vault_key" "etcd" {
  count = var.enable_kms_etcd_encryption ? 1 : 0

  name         = "kms-etcd-${local.name_prefix}"
  key_vault_id = module.key_vault.resource_id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P90D"
    notify_before_expiry = "P29D"
  }

  depends_on = [azurerm_role_assignment.deployer_kms_crypto_officer]
}
