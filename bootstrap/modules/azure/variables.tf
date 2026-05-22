# --- Naming / location ---------------------------------------------------------
variable "azure_location" {
  description = "Azure region for bootstrap resources."
  type        = string
}

variable "resource_names" {
  description = "Resolved resource names map from the resource_names module."
  type        = map(string)
}

# --- Subscription topology -----------------------------------------------------
variable "aks_landing_zone_subscription_id" {
  description = "Subscription where the AKS landing zone will be deployed by the generated pipeline."
  type        = string
}

variable "bootstrap_subscription_id" {
  description = "Subscription where bootstrap resources (state SA, ACR, ACI runners, MIs) live."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Subscription hosting the hub VNet and firewall."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

# --- Identity / OIDC -----------------------------------------------------------
variable "github_organization_name" {
  description = "GitHub organization that will host the workload repo (used for federated subject)."
  type        = string
}

variable "managed_identities" {
  description = <<-EOT
    Map of UAMI logical names => federated credential definitions.
    Typical keys: 'plan', 'apply'.
  EOT
  type = map(object({
    federated_credentials = map(object({
      subject = string
    }))
    role_assignments = list(object({
      scope                = string
      role_definition_name = string
    }))
  }))
}

# --- Self-hosted runners (ACI) -------------------------------------------------
variable "use_self_hosted_runners" {
  description = "If true, build the runner image and create ACI runner containers."
  type        = bool
  default     = true
}

variable "use_private_networking" {
  description = "If true, deploy VNet, NAT gateway, private endpoints, and disable public access on the storage account."
  type        = bool
  default     = true
}

variable "runner_count" {
  description = "Number of ACI runner instances to create."
  type        = number
  default     = 2
}

variable "runner_container_image_tag" {
  description = "Image tag for the runner image built into ACR."
  type        = string
  default     = "latest"
}

variable "github_runners_personal_access_token" {
  description = "Fine-grained PAT used by the ACI runners to register with the GitHub organization."
  type        = string
  sensitive   = true
  default     = ""
}

# --- Networking ----------------------------------------------------------------
variable "virtual_network_address_space" {
  description = "Bootstrap VNet address space."
  type        = string
  default     = "10.100.0.0/24"
}

variable "subnet_address_prefix_container_instances" {
  description = "Subnet CIDR for ACI runners."
  type        = string
  default     = "10.100.0.0/26"
}

variable "subnet_address_prefix_private_endpoints" {
  description = "Subnet CIDR for private endpoints."
  type        = string
  default     = "10.100.0.64/27"
}

# --- Storage -------------------------------------------------------------------
variable "storage_account_replication_type" {
  description = "Replication SKU for the Terraform state storage account."
  type        = string
  default     = "ZRS"
}
