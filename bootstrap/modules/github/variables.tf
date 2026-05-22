variable "organization_name" {
  description = "GitHub organization that owns the workload repository."
  type        = string
}

variable "repository_name" {
  description = "Name of the workload repository to create or update."
  type        = string
}

variable "repository_description" {
  description = "Description applied to the workload repository."
  type        = string
  default     = "AKS Application Landing Zone — managed by bootstrap Terraform."
}

variable "environments" {
  description = <<-EOT
    Map of GitHub Actions environments (e.g. 'plan', 'apply') with their
    reviewer settings and Azure linkage.
  EOT
  type = map(object({
    reviewers_team_ids = optional(list(number), [])
    reviewers_users    = optional(list(string), [])
    wait_timer         = optional(number, 0)
  }))
  default = {}
}

variable "approvers" {
  description = "GitHub usernames that approve apply runs."
  type        = list(string)
  default     = []
}

variable "team_name" {
  description = "Name of the team granted approve rights on the apply environment."
  type        = string
  default     = ""
}

variable "create_team" {
  description = "If true, create a new approvers team; otherwise use existing_team_name."
  type        = bool
  default     = true
}

variable "existing_team_name" {
  description = "Existing team name to use when create_team = false."
  type        = string
  default     = ""
}

# --- Backend / Azure wiring exposed as Actions variables ----------------------
variable "azure_tenant_id" {
  description = "Tenant ID to expose to GitHub Actions."
  type        = string
}

variable "azure_subscription_id" {
  description = "Landing-zone subscription ID exposed to GitHub Actions."
  type        = string
}

variable "managed_identity_client_ids" {
  description = "Map of environment => UAMI client ID for OIDC login (keys must match environments map)."
  type        = map(string)
  default     = {}
}

variable "backend_resource_group_name" {
  description = "RG of the Terraform state storage account."
  type        = string
}

variable "backend_storage_account_name" {
  description = "Name of the Terraform state storage account."
  type        = string
}

variable "backend_storage_container_name" {
  description = "Blob container holding Terraform state."
  type        = string
}

# --- Files pushed into the repo -----------------------------------------------
variable "repository_files" {
  description = "Map of repo-relative path => file content rendered by the wizard."
  type        = map(string)
  default     = {}
}

# --- Self-hosted runner group --------------------------------------------------
variable "use_runner_group" {
  description = "If true, create and target a custom runner group for self-hosted runners."
  type        = bool
  default     = true
}

variable "runner_group_name" {
  description = "Name of the GitHub Actions runner group."
  type        = string
  default     = ""
}
