variable "connectivity_subscription_id" {
  description = "Subscription that hosts the hub VNet + firewall."
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID."
  type        = string
}

variable "location" {
  description = "Azure region for the hub."
  type        = string
}

variable "service_name" {
  description = "Short service identifier; used to derive default resource names."
  type        = string
}

variable "environment_name" {
  description = "Environment token; used to derive default resource names."
  type        = string
}

variable "postfix_number" {
  description = "Numeric postfix for uniqueness."
  type        = number
  default     = 1
}

variable "hub_vnet_address_space" {
  description = "Hub VNet address space, e.g. ['10.0.0.0/16']."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "deploy_firewall" {
  description = "If true, deploy an Azure Firewall + policy + public IP."
  type        = bool
  default     = true
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier. Allowed: Standard, Premium."
  type        = string
  default     = "Standard"
}

variable "firewall_subnet_address_prefix" {
  description = "Address prefix for AzureFirewallSubnet (must be /26 or larger)."
  type        = string
  default     = "10.0.0.0/26"
}

variable "tags" {
  description = "Tags applied to all hub resources."
  type        = map(string)
  default     = {}
}
