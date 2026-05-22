# Ensure Microsoft.ContainerInstance is registered on the bootstrap subscription.
resource "azurerm_resource_provider_registration" "container_instance" {
  count = var.use_self_hosted_runners ? 1 : 0
  name  = "Microsoft.ContainerInstance"
}
