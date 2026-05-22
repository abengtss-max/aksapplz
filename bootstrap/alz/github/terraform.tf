terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.20"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.2"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # Bootstrap starts with local state. After apply, the wizard migrates state to
  # the storage account created by the azure module via `terraform init -migrate-state`.
}

provider "azurerm" {
  subscription_id = var.bootstrap_subscription_id
  tenant_id       = var.tenant_id
  features {}
  resource_provider_registrations = "none"
}

provider "azapi" {
  subscription_id = var.bootstrap_subscription_id
  tenant_id       = var.tenant_id
}

provider "azuread" {
  tenant_id = var.tenant_id
}

provider "github" {
  owner = var.github_organization_name
  token = var.github_personal_access_token
}
