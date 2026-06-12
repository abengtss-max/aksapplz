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

  # PAT auth (default). When the PAT is empty (OIDC-only mode), token is null so
  # the provider falls back to GITHUB_TOKEN/GH_TOKEN from the environment or to
  # the app_auth block below.
  token = var.github_personal_access_token != "" ? var.github_personal_access_token : null

  # GitHub App auth (PAT-less). Enabled only when all three app inputs are set
  # (typically via TF_VAR_github_app_* from -OidcOnly). Mutually exclusive with a
  # non-empty token, which is why token is null in that case.
  dynamic "app_auth" {
    for_each = (var.github_app_id != "" && var.github_app_installation_id != "" && var.github_app_pem_file != "") ? [1] : []
    content {
      id              = var.github_app_id
      installation_id = var.github_app_installation_id
      pem_file        = file(var.github_app_pem_file)
    }
  }
}
