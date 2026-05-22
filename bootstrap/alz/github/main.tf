module "resource_names" {
  source           = "../../modules/resource_names"
  azure_location   = var.bootstrap_location
  service_name     = var.service_name
  environment_name = var.environment_name
  postfix_number   = var.postfix_number
  resource_names   = merge(local.default_resource_names, var.resource_names)
}

# Phase 5 will wire the azure module here.
# module "azure" {
#   source = "../../modules/azure"
#   ...
# }

# Phase 6 will wire the github module here.
# module "github" {
#   source = "../../modules/github"
#   ...
# }
