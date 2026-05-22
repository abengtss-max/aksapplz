locals {
  acr_sku = var.use_private_networking ? "Premium" : "Basic"
}

module "container_registry" {
  count   = var.use_self_hosted_runners ? 1 : 0
  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "~> 0.5"

  name                = var.resource_names["container_registry"]
  resource_group_name = azurerm_resource_group.agents[0].name
  location            = var.azure_location
  sku                 = local.acr_sku

  # ACR Tasks run on Azure-managed public agents and cannot reach a private-only
  # registry. Keep public access enabled (with AzureServices bypass) so the runner
  # image can be built; private endpoint still provides in-VNet routing.
  public_network_access_enabled = true
  network_rule_bypass_option    = "AzureServices"
  zone_redundancy_enabled       = var.use_private_networking

  enable_telemetry = false
  tags             = var.tags
}

# Build the runner image via an ACR Task using the upstream ALZ Dockerfile.
resource "azurerm_container_registry_task" "runner_image" {
  count                 = var.use_self_hosted_runners ? 1 : 0
  name                  = "build-${var.resource_names["container_image_name"]}"
  container_registry_id = module.container_registry[0].resource_id

  platform {
    os = "Linux"
  }

  docker_step {
    dockerfile_path      = "Dockerfile"
    context_path         = "https://github.com/Azure/avm-container-images-cicd-agents-and-runners.git#57a937f:github-runner-aci"
    context_access_token = "ignored" # public repo, but provider requires a value
    image_names          = ["${var.resource_names["container_image_name"]}:${var.runner_container_image_tag}"]
    push_enabled         = true
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "runner_image" {
  count                      = var.use_self_hosted_runners ? 1 : 0
  container_registry_task_id = azurerm_container_registry_task.runner_image[0].id
}
