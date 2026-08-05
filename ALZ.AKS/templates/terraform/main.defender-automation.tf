# -----------------------------------------------------------------------------
# Root - Defender for Cloud -> GitHub work-item automation (issue #37)
#
# Turns Microsoft Defender for Cloud security ALERTS into tracked GitHub Issues
# automatically, instead of relying on manual review of the Defender/Grafana
# dashboards (#35, #36). The flow is:
#
#   Defender for Cloud alert
#     -> Microsoft.Security/automations (Workflow Automation, severity-filtered)
#       -> Consumption Logic App (HTTP-triggered)
#         -> reads a GitHub token from Key Vault at RUNTIME (managed identity)
#         -> POST https://api.github.com/repos/<owner/repo>/issues
#
# Design notes:
# - Entirely OPT-IN (enable_defender_workflow_automation + defender_ticketing_
#   target = "github"). Nothing is created - and no cost is incurred - by
#   default.
# - GitHub-only for now. defender_ticketing_target keeps the door open for
#   "azuredevops" / "servicenow" later without another breaking change.
# - The GitHub token is NEVER inlined. It lives as a Key Vault secret and is
#   fetched by the Logic App's system-assigned managed identity at run time, so
#   it never lands in Terraform state or the workflow definition.
# - Severity filtering happens in the Defender automation rule set (one OR'd
#   rule set per included severity), so lower-severity alerts never even reach
#   the Logic App.
#
# NETWORKING CAVEAT (private deployments): a Consumption Logic App runs on the
# Azure multi-tenant Logic Apps service and reaches the Key Vault over its
# PUBLIC endpoint. When the primary Key Vault has public access disabled
# (enable_private_endpoints), the runtime secret fetch cannot reach it. In that
# case, store the token in a Key Vault that permits trusted Azure services (or a
# dedicated ticketing Key Vault), or move to a VNet-integrated Standard Logic
# App (tracked in #42). See docs/concepts/defender-ticketing.md.
# -----------------------------------------------------------------------------

locals {
  # Feature is live only when explicitly enabled AND targeting GitHub.
  defender_ticketing_github_enabled = var.enable_defender_workflow_automation && var.defender_ticketing_target == "github"

  # Minimum-severity -> included severities (OR semantics across rule sets).
  _defender_severity_tiers = {
    Low    = ["Low", "Medium", "High"]
    Medium = ["Medium", "High"]
    High   = ["High"]
  }
  defender_ticketing_severities = local._defender_severity_tiers[var.defender_ticketing_min_severity]

  # Names + trigger identifier.
  defender_ticketing_logic_app_name  = "logic-${local.name_prefix}-defender-tickets"
  defender_ticketing_automation_name = "sca-${local.name_prefix}-defender-tickets"
  defender_ticketing_trigger_name    = "When_a_Defender_alert_is_received"

  # Runtime GitHub token source: a secret in the primary-region Key Vault.
  # key_vault_uri already ends in "/" (e.g. https://kv-....vault.azure.net/).
  defender_ticketing_token_secret_uri = "${module.region["primary"].key_vault_uri}secrets/${var.defender_ticketing_github_pat_secret_name}?api-version=7.4"
  defender_ticketing_github_issue_url = "https://api.github.com/repos/${var.defender_ticketing_github_repository}/issues"
}

# -----------------------------------------------------------------------------
# Consumption Logic App: reads the GitHub token from Key Vault (managed
# identity) and creates a GitHub issue from the Defender alert payload.
# -----------------------------------------------------------------------------
resource "azapi_resource" "defender_ticketing_logic_app" {
  count = local.defender_ticketing_github_enabled ? 1 : 0

  type      = "Microsoft.Logic/workflows@2019-05-01"
  name      = local.defender_ticketing_logic_app_name
  parent_id = module.region["primary"].resource_group_id
  location  = module.region["primary"].location
  tags      = local.default_tags

  identity {
    type = "SystemAssigned"
  }

  body = {
    properties = {
      state = "Enabled"
      definition = {
        "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
        contentVersion = "1.0.0.0"
        parameters     = {}
        triggers = {
          (local.defender_ticketing_trigger_name) = {
            type = "Request"
            kind = "Http"
            inputs = {
              schema = {}
            }
          }
        }
        actions = {
          # Fetch the GitHub token from Key Vault using the Logic App's MSI.
          Get_GitHub_token = {
            type     = "Http"
            runAfter = {}
            inputs = {
              method = "GET"
              uri    = local.defender_ticketing_token_secret_uri
              authentication = {
                type     = "ManagedServiceIdentity"
                audience = "https://vault.azure.net"
              }
            }
            # Don't echo the secret into the run history.
            runtimeConfiguration = {
              secureData = {
                properties = ["outputs"]
              }
            }
          }
          # Create the GitHub issue.
          Create_GitHub_issue = {
            type = "Http"
            runAfter = {
              Get_GitHub_token = ["Succeeded"]
            }
            inputs = {
              method = "POST"
              uri    = local.defender_ticketing_github_issue_url
              headers = {
                "Authorization"        = "Bearer @{body('Get_GitHub_token')?['value']}"
                "Accept"               = "application/vnd.github+json"
                "Content-Type"         = "application/json"
                "User-Agent"           = "aksapplz-defender-automation"
                "X-GitHub-Api-Version" = "2022-11-28"
              }
              body = {
                title  = "[Defender][@{coalesce(triggerBody()?['Severity'], 'Unknown')}] @{coalesce(triggerBody()?['AlertDisplayName'], triggerBody()?['DisplayName'], 'Defender for Cloud finding')}"
                labels = var.defender_ticketing_github_labels
                body   = "A Microsoft Defender for Cloud finding was reported for this landing zone.\n\n| Field | Value |\n|---|---|\n| **Severity** | @{coalesce(triggerBody()?['Severity'], 'Unknown')} |\n| **Alert** | @{coalesce(triggerBody()?['AlertDisplayName'], triggerBody()?['DisplayName'], 'n/a')} |\n| **Affected resource** | @{coalesce(triggerBody()?['CompromisedEntity'], 'n/a')} |\n| **Product** | @{coalesce(triggerBody()?['ProductName'], 'Microsoft Defender for Cloud')} |\n| **Time (UTC)** | @{coalesce(triggerBody()?['TimeGeneratedUtc'], triggerBody()?['StartTimeUtc'], '')} |\n\n**Description**\n\n@{coalesce(triggerBody()?['Description'], 'No description provided.')}\n\n**Remediation**\n\n@{coalesce(triggerBody()?['RemediationSteps'], 'See Microsoft Defender for Cloud.')}\n\n[View in Microsoft Defender for Cloud](@{coalesce(triggerBody()?['AlertUri'], 'https://portal.azure.com')})\n\n---\n_Filed automatically by the AKS Application Landing Zone Accelerator (Defender workflow automation, issue #37)._"
              }
            }
          }
        }
        outputs = {}
      }
    }
  }

  response_export_values = ["identity.principalId"]

  lifecycle {
    precondition {
      condition     = !local.defender_ticketing_github_enabled || (var.defender_ticketing_github_repository != "" && var.defender_ticketing_github_pat_secret_name != "")
      error_message = "When enable_defender_workflow_automation = true and defender_ticketing_target = \"github\", you must set defender_ticketing_github_repository (owner/repo) and defender_ticketing_github_pat_secret_name (the Key Vault secret holding a GitHub token with Issues:write)."
    }
  }
}

# -----------------------------------------------------------------------------
# Grant the Logic App's managed identity read access to the token secret.
# -----------------------------------------------------------------------------
resource "azurerm_role_assignment" "defender_ticketing_kv_secrets_user" {
  count = local.defender_ticketing_github_enabled ? 1 : 0

  scope                = module.region["primary"].key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azapi_resource.defender_ticketing_logic_app[0].output.identity.principalId
}

# -----------------------------------------------------------------------------
# The callback URL (with SAS signature) that the Defender automation POSTs to.
# -----------------------------------------------------------------------------
resource "azapi_resource_action" "defender_ticketing_callback" {
  count = local.defender_ticketing_github_enabled ? 1 : 0

  type        = "Microsoft.Logic/workflows@2019-05-01"
  resource_id = "${azapi_resource.defender_ticketing_logic_app[0].id}/triggers/${local.defender_ticketing_trigger_name}"
  action      = "listCallbackUrl"
  method      = "POST"

  response_export_values = ["value"]
}

# -----------------------------------------------------------------------------
# Defender for Cloud Workflow Automation: on each qualifying security alert,
# invoke the Logic App. Scoped to the whole subscription; severity-filtered.
# -----------------------------------------------------------------------------
resource "azurerm_security_center_automation" "defender_ticketing" {
  count = local.defender_ticketing_github_enabled ? 1 : 0

  name                = local.defender_ticketing_automation_name
  location            = module.region["primary"].location
  resource_group_name = module.region["primary"].resource_group_name
  scopes              = ["/subscriptions/${var.subscription_id}"]
  tags                = local.default_tags

  action {
    type        = "LogicApp"
    resource_id = azapi_resource.defender_ticketing_logic_app[0].id
    trigger_url = azapi_resource_action.defender_ticketing_callback[0].output.value
  }

  # One rule set per included severity; rule sets are OR'd together, so this
  # matches "severity is any of the included tiers".
  source {
    event_source = "Alerts"

    dynamic "rule_set" {
      for_each = local.defender_ticketing_severities
      content {
        rule {
          property_path  = "Severity"
          operator       = "Equals"
          expected_value = rule_set.value
          property_type  = "String"
        }
      }
    }
  }
}
