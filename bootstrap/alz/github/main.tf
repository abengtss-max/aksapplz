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
