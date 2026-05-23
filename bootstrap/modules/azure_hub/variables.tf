variable "location" {
  description = "Azure region for hub resources."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the hub resource group (created by this module)."
  type        = string
}

variable "vnet_name" {
  description = "Name of the hub VNet."
  type        = string
}

variable "vnet_address_space" {
  description = "Hub VNet address space, e.g. ['10.0.0.0/16']."
  type        = list(string)
}

variable "deploy_firewall" {
  description = "If true, deploy an Azure Firewall + policy + public IP. The AzureFirewallSubnet is always created."
  type        = bool
  default     = true
}

variable "firewall_sku_tier" {
  description = "Azure Firewall SKU tier. Allowed: Standard, Premium. (Basic is not supported by this module in v1.3 because it requires a Management subnet + IP.)"
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be Standard or Premium."
  }
}

variable "firewall_subnet_address_prefix" {
  description = "Address prefix for AzureFirewallSubnet (must be /26 or larger)."
  type        = string
  default     = "10.0.0.0/26"
}

variable "firewall_name" {
  description = "Name of the Azure Firewall."
  type        = string
  default     = ""
}

variable "firewall_public_ip_name" {
  description = "Name of the firewall's public IP."
  type        = string
  default     = ""
}

variable "firewall_policy_name" {
  description = "Name of the firewall policy."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all hub resources."
  type        = map(string)
  default     = {}
}
