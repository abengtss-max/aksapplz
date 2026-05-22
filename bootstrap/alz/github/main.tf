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

# Phase 6 will wire the github module here.
# module "github" {
#   source = "../../modules/github"
#   ...
# }
