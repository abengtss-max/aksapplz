terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.connectivity_subscription_id
  tenant_id       = var.tenant_id
}
