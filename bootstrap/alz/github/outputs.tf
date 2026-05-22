output "resource_names" {
  description = "Resolved resource names — useful for debugging the rendering."
  value       = module.resource_names.resource_names
}

# --- Backend coordinates (consumed by wizard to migrate state) -----------------
output "backend_resource_group_name" {
  description = "Resource group name for the Terraform backend."
  value       = module.azure.state_resource_group_name
}

output "backend_storage_account_name" {
  description = "Storage account name for the Terraform backend."
  value       = module.azure.state_storage_account_name
}

output "backend_container_name" {
  description = "Container name for the Terraform backend."
  value       = module.azure.state_container_name
}

# --- Identity / runners --------------------------------------------------------
output "managed_identity_client_ids" {
  description = "Per-environment MI client IDs for OIDC (plan/apply/aci_runner)."
  value       = module.azure.managed_identity_client_ids
}

output "container_registry_login_server" {
  description = "ACR login server (empty when self-hosted runners disabled)."
  value       = module.azure.container_registry_login_server
}

output "runner_image" {
  description = "Runner image FQN built into ACR."
  value       = module.azure.runner_image
}
