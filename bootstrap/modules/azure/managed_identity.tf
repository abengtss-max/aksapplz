locals {
  managed_identity_names = {
    plan       = var.resource_names["managed_identity_plan"]
    apply      = var.resource_names["managed_identity_apply"]
    aci_runner = var.resource_names["container_instance_managed_identity"]
  }
}

module "managed_identities" {
  source   = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version  = "~> 0.5"
  for_each = local.managed_identity_names

  name                = each.value
  resource_group_name = azurerm_resource_group.identity.name
  location            = var.azure_location
  enable_telemetry    = false
  tags                = var.tags
}
