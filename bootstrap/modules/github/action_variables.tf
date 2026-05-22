# Per-environment OIDC client ID (one UAMI per environment).
resource "github_actions_environment_variable" "azure_client_id" {
  for_each      = var.managed_identity_client_ids
  repository    = github_repository.this.name
  environment   = github_repository_environment.this[each.key].environment
  variable_name = "AZURE_CLIENT_ID"
  value         = each.value
}

# Repo-level Azure context.
resource "github_actions_variable" "azure_tenant_id" {
  repository    = github_repository.this.name
  variable_name = "AZURE_TENANT_ID"
  value         = var.azure_tenant_id
}

resource "github_actions_variable" "azure_subscription_id" {
  repository    = github_repository.this.name
  variable_name = "AZURE_SUBSCRIPTION_ID"
  value         = var.azure_subscription_id
}

# Repo-level Terraform backend coordinates.
resource "github_actions_variable" "backend_resource_group_name" {
  repository    = github_repository.this.name
  variable_name = "BACKEND_AZURE_RESOURCE_GROUP_NAME"
  value         = var.backend_resource_group_name
}

resource "github_actions_variable" "backend_storage_account_name" {
  repository    = github_repository.this.name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_NAME"
  value         = var.backend_storage_account_name
}

resource "github_actions_variable" "backend_storage_container_name" {
  repository    = github_repository.this.name
  variable_name = "BACKEND_AZURE_STORAGE_ACCOUNT_CONTAINER_NAME"
  value         = var.backend_storage_container_name
}

# Runner group name (used by workflow runs-on labels).
resource "github_actions_variable" "runner_group_name" {
  count         = local.use_runner_group ? 1 : 0
  repository    = github_repository.this.name
  variable_name = "RUNNER_GROUP_NAME"
  value         = github_actions_runner_group.this[0].name
}
