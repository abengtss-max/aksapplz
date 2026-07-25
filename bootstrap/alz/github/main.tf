module "resource_names" {
  source           = "../../modules/resource_names"
  azure_location   = var.bootstrap_location
  service_name     = var.service_name
  environment_name = var.environment_name
  postfix_number   = var.postfix_number
  resource_names   = merge(local.default_resource_names, var.resource_names)
}

module "azure" {
  source = "../../modules/azure"

  azure_location                       = var.bootstrap_location
  resource_names                       = module.resource_names.resource_names
  aks_landing_zone_subscription_id     = var.aks_landing_zone_subscription_id
  bootstrap_subscription_id            = var.bootstrap_subscription_id
  connectivity_subscription_id         = var.connectivity_subscription_id
  tenant_id                            = var.tenant_id
  github_organization_name             = var.github_organization_name
  repository_name                      = module.resource_names.resource_names["version_control_system_repository"]
  use_self_hosted_runners              = var.use_self_hosted_runners
  use_private_networking               = var.use_private_networking
  github_runners_personal_access_token = var.github_runners_personal_access_token
  tags                                 = var.tags
}

module "github" {
  source = "../../modules/github"

  organization_name      = var.github_organization_name
  repository_name        = module.resource_names.resource_names["version_control_system_repository"]
  repository_description = "AKS application landing zone — managed by aksapplz bootstrap."

  environments = local.environments
  approvers    = var.apply_approvers
  create_team  = length(var.apply_approvers) > 0
  team_name    = module.resource_names.resource_names["version_control_system_team"]

  azure_tenant_id             = var.tenant_id
  azure_subscription_id       = var.aks_landing_zone_subscription_id
  managed_identity_client_ids = module.azure.managed_identity_client_ids

  backend_resource_group_name    = module.azure.state_resource_group_name
  backend_storage_account_name   = module.azure.state_storage_account_name
  backend_storage_container_name = module.azure.state_container_name

  repository_files = var.repository_files

  use_runner_group  = var.use_self_hosted_runners
  runner_group_name = module.resource_names.resource_names["version_control_system_runner_group"]
}

# -----------------------------------------------------------------------------
# GitHub OIDC federated credentials for the plan/apply managed identities.
#
# Created here (not inside module.azure) because the subject must reference the
# GitHub repository, which is provisioned by module.github. Keeping the FICs at
# the composition root lets them depend on BOTH the managed identities (azure)
# and the repository (github) without introducing a module dependency cycle.
#
# GitHub is rolling out IMMUTABLE OIDC subject claims that embed the numeric
# org/repo database IDs, e.g.:
#   repo:<org>@<orgId>/<repo>@<repoId>:environment:plan
# Non-enrolled repositories still present the legacy name-based subject:
#   repo:<org>/<repo>:environment:plan
# We register BOTH subjects per environment so pipeline authentication succeeds
# regardless of the organization's enrollment state (the GitHub-recommended
# migration pattern). Extra unmatched credentials are harmless.
# -----------------------------------------------------------------------------
locals {
  workload_repository_name = module.resource_names.resource_names["version_control_system_repository"]

  oidc_legacy_prefix    = "repo:${var.github_organization_name}/${local.workload_repository_name}"
  oidc_immutable_prefix = "repo:${var.github_organization_name}@${module.github.organization_database_id}/${local.workload_repository_name}@${module.github.repository_database_id}"

  federated_credentials = merge(
    {
      for env in ["plan", "apply"] :
      env => {
        identity = env
        name     = "fc-github-${env}"
        subject  = "${local.oidc_legacy_prefix}:environment:${env}"
      }
    },
    {
      for env in ["plan", "apply"] :
      "${env}-immutable" => {
        identity = env
        name     = "fc-github-${env}-immutable"
        subject  = "${local.oidc_immutable_prefix}:environment:${env}"
      }
    }
  )
}

resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_credentials

  name                = each.value.name
  resource_group_name = module.azure.identity_resource_group_name
  parent_id           = module.azure.managed_identity_resource_ids[each.value.identity]
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = each.value.subject
}

# Adopt the legacy name-based FICs that previously lived inside module.azure so
# upgrades don't destroy/recreate them (the immutable variants are additive).
moved {
  from = module.azure.azurerm_federated_identity_credential.github["plan"]
  to   = azurerm_federated_identity_credential.github["plan"]
}

moved {
  from = module.azure.azurerm_federated_identity_credential.github["apply"]
  to   = azurerm_federated_identity_credential.github["apply"]
}
