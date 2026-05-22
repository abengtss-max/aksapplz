output "state_resource_group_name" {
  description = "Resource group hosting the Terraform state storage account."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account_name" {
  description = "Name of the Terraform state storage account."
  value       = module.storage_account.name
}

output "state_storage_account_id" {
  description = "Resource ID of the Terraform state storage account."
  value       = module.storage_account.resource_id
}

output "state_container_name" {
  description = "Blob container name for Terraform state."
  value       = module.storage_account.containers["tfstate"].name
}

output "managed_identity_client_ids" {
  description = "Map of logical MI name => client ID, suitable for ARM_CLIENT_ID."
  value = {
    for k, m in module.managed_identities : k => m.client_id
  }
}

output "managed_identity_principal_ids" {
  description = "Map of logical MI name => principal (object) ID."
  value = {
    for k, m in module.managed_identities : k => m.principal_id
  }
}

output "container_registry_login_server" {
  description = "ACR login server FQDN (empty when self-hosted runners disabled)."
  value       = var.use_self_hosted_runners ? module.container_registry[0].resource.login_server : ""
}

output "runner_image" {
  description = "Fully qualified runner image name pushed to ACR."
  value       = local.runner_image_fqn
}

output "runner_container_group_ids" {
  description = "Resource IDs of the ACI runner container groups."
  value       = [for cg in azurerm_container_group.runner : cg.id]
}

output "virtual_network_id" {
  description = "Bootstrap VNet resource ID (empty when private networking disabled)."
  value       = var.use_private_networking ? module.virtual_network[0].resource_id : ""
}
