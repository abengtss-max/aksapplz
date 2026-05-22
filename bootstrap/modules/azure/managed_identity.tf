locals {
  managed_identity_names = {
    plan       = var.resource_names["managed_identity_plan"]
    apply      = var.resource_names["managed_identity_apply"]
    aci_runner = var.resource_names["container_instance_managed_identity"]
  }

  federated_subjects = {
    plan = {
      issuer  = "https://token.actions.githubusercontent.com"
      subject = "repo:${var.github_organization_name}/${var.repository_name}:environment:plan"
    }
    apply = {
      issuer  = "https://token.actions.githubusercontent.com"
      subject = "repo:${var.github_organization_name}/${var.repository_name}:environment:apply"
    }
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

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_subjects

  name                = "fc-github-${each.key}"
  resource_group_name = azurerm_resource_group.identity.name
  parent_id           = module.managed_identities[each.key].resource_id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = each.value.issuer
  subject             = each.value.subject
}
