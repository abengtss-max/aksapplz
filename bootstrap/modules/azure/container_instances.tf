locals {
  runner_image_fqn = var.use_self_hosted_runners ? "${module.container_registry[0].resource.login_server}/${var.resource_names["container_image_name"]}:${var.runner_container_image_tag}" : ""

  runner_instances = var.use_self_hosted_runners ? {
    for i in range(var.runner_count) :
    format("%02d", i + 1) => {
      name = "${var.resource_names["container_registry"]}-runner-${format("%02d", i + 1)}"
    }
  } : {}
}

resource "azurerm_container_group" "runner" {
  for_each            = local.runner_instances
  name                = each.value.name
  location            = var.azure_location
  resource_group_name = azurerm_resource_group.agents[0].name
  os_type             = "Linux"
  restart_policy      = "Always"
  zones               = ["1"]

  ip_address_type = var.use_private_networking ? "Private" : "Public"
  subnet_ids      = var.use_private_networking ? [module.virtual_network[0].subnets["container_instances"].resource_id] : null

  identity {
    type         = "UserAssigned"
    identity_ids = [module.managed_identities["aci_runner"].resource_id]
  }

  image_registry_credential {
    server                    = module.container_registry[0].resource.login_server
    user_assigned_identity_id = module.managed_identities["aci_runner"].resource_id
  }

  container {
    name   = "runner"
    image  = local.runner_image_fqn
    cpu    = 4
    memory = 16

    environment_variables = {
      GH_RUNNER_URL  = "https://github.com/${var.github_organization_name}"
      GH_RUNNER_NAME = each.value.name
      GH_RUNNER_MODE = "persistent"
    }

    secure_environment_variables = {
      GH_RUNNER_TOKEN = var.github_runners_personal_access_token
    }

    ports {
      port     = 80
      protocol = "TCP"
    }
  }

  tags = var.tags

  depends_on = [
    azurerm_container_registry_task_schedule_run_now.runner_image,
    azurerm_role_assignment.aci_runner_acrpull,
  ]
}
