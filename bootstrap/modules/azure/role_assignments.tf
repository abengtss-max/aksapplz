# State container RBAC is managed inline in storage.tf via the storage module's
# `containers.role_assignments` argument.

# Landing zone subscription: apply MI gets Contributor + UAA.
resource "azurerm_role_assignment" "apply_lz_contributor" {
  scope                = "/subscriptions/${var.aks_landing_zone_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = module.managed_identities["apply"].principal_id
}

resource "azurerm_role_assignment" "apply_lz_uaa" {
  scope                = "/subscriptions/${var.aks_landing_zone_subscription_id}"
  role_definition_name = "User Access Administrator"
  principal_id         = module.managed_identities["apply"].principal_id
}

resource "azurerm_role_assignment" "plan_lz_reader" {
  scope                = "/subscriptions/${var.aks_landing_zone_subscription_id}"
  role_definition_name = "Reader"
  principal_id         = module.managed_identities["plan"].principal_id
}

# ACR: ACI runner MI gets AcrPull.
resource "azurerm_role_assignment" "aci_runner_acrpull" {
  count                = var.use_self_hosted_runners ? 1 : 0
  scope                = module.container_registry[0].resource_id
  role_definition_name = "AcrPull"
  principal_id         = module.managed_identities["aci_runner"].principal_id
}
