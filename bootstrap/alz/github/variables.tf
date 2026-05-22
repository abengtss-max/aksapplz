# --- Scenario / location -------------------------------------------------------
variable "scenario" {
  description = "Deployment scenario (single_region_baseline | single_region_regulated | multi_region_*)."
  type        = string
  default     = "single_region_baseline"
}

variable "bootstrap_location" {
  description = "Azure region for bootstrap resources."
  type        = string
}

variable "secondary_location" {
  description = "Secondary region (multi-region scenarios)."
  type        = string
  default     = ""
}

# --- Naming -------------------------------------------------------------------
variable "service_name" {
  description = "Short service identifier (e.g. 'aksapplz')."
  type        = string
}

variable "environment_name" {
  description = "Environment token (e.g. 'prod', 'dev')."
  type        = string
}

variable "postfix_number" {
  description = "Numeric postfix for uniqueness."
  type        = number
  default     = 1
}

variable "resource_names" {
  description = "Optional overrides for individual resource name templates."
  type        = map(string)
  default     = {}
}

# --- Subscriptions / identity --------------------------------------------------
variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "bootstrap_subscription_id" {
  description = "Subscription hosting bootstrap resources."
  type        = string
}

variable "aks_landing_zone_subscription_id" {
  description = "Subscription where the AKS landing zone will be deployed."
  type        = string
}

variable "connectivity_subscription_id" {
  description = "Subscription hosting hub VNet."
  type        = string
}

# --- Hub networking ------------------------------------------------------------
variable "hub_vnet_resource_id" {
  description = "Resource ID of the hub VNet for peering."
  type        = string
}

variable "hub_vnet_name" {
  description = "Hub VNet name."
  type        = string
  default     = ""
}

variable "hub_vnet_resource_group_name" {
  description = "Hub VNet resource group."
  type        = string
  default     = ""
}

variable "hub_firewall_private_ip" {
  description = "Hub firewall private IP (used in UDRs)."
  type        = string
  default     = ""
}

# --- GitHub --------------------------------------------------------------------
variable "github_organization_name" {
  description = "GitHub org that will host the workload repository."
  type        = string
}

variable "github_personal_access_token" {
  description = "Fine-grained PAT with admin:org + repo scopes (read via TF_VAR_github_personal_access_token)."
  type        = string
  sensitive   = true
}

variable "github_runners_personal_access_token" {
  description = "Fine-grained PAT used by ACI runners for org-level registration."
  type        = string
  sensitive   = true
  default     = ""
}

variable "apply_approvers" {
  description = "GitHub usernames that approve apply runs."
  type        = list(string)
  default     = []
}

# --- Bootstrap features --------------------------------------------------------
variable "use_self_hosted_runners" {
  description = "Build ACR image + create ACI runners + runner group."
  type        = bool
  default     = true
}

variable "use_private_networking" {
  description = "Disable public access on bootstrap state SA + ACR, use VNet + PEs."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all bootstrap resources."
  type        = map(string)
  default = {
    managedBy = "aksapplz-bootstrap-terraform"
  }
}

# --- Pass-through (rendered into repo files; not consumed by bootstrap) -------
variable "aks_landing_zone_inputs" {
  description = "Free-form pass-through map written verbatim into the workload repo's tfvars."
  type        = map(any)
  default     = {}
}
