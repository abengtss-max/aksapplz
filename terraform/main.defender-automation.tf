# -----------------------------------------------------------------------------
# Root - Defender for Cloud workflow automation -> ticketing (#37)
#
# Auto-creates work items from Microsoft Defender for Cloud security alerts by
# routing High-severity alerts to a Logic App via a Security Center automation
# (Microsoft.Security/automations). The Logic App is the integration point that
# a connector step (GitHub Issues / Azure DevOps / ServiceNow) is wired into to
# open the ticket.
#
# This is a terraform-validate-clean, DEFAULT-OFF scaffold:
#   * enable_defender_workflow_automation gates every resource (default false).
#   * defender_ticketing_target records the intended connector so the remaining
#     wiring (connector API connection + Key Vault-backed credentials) can be
#     completed and live-validated deliberately.
#
# SECURITY: no credentials are stored here. When wiring a connector, store its
# secret in Key Vault and grant this Logic App's system-assigned managed
# identity the "Key Vault Secrets User" role on that vault - never inline a
# secret in the workflow definition.
# -----------------------------------------------------------------------------

variable "enable_defender_workflow_automation" {
  description = "Create a Defender for Cloud workflow automation that routes High-severity security alerts to a Logic App for automatic ticket creation. Opt-in (default false). The connector step (GitHub/Azure DevOps/ServiceNow) is wired into the Logic App as a follow-up; see defender_ticketing_target."
  type        = bool
  default     = false
}

variable "defender_ticketing_target" {
  description = "Intended ticketing connector for the Defender workflow automation Logic App: 'github', 'azuredevops', 'servicenow' or 'none'. Recorded as a tag/hint; the connector API connection and its Key Vault-backed credentials are wired in as a follow-up step."
  type        = string
  default     = "none"
  validation {
    condition     = contains(["github", "azuredevops", "servicenow", "none"], var.defender_ticketing_target)
    error_message = "defender_ticketing_target must be one of: github, azuredevops, servicenow, none."
  }
}

locals {
  secops_enabled  = var.enable_defender_workflow_automation
  secops_rg_name  = "rg-${var.workload_name}-${var.environment}-secops"
  secops_la_name  = "logic-${var.workload_name}-${var.environment}-defender-ticketing"
  secops_aut_name = "aut-${var.workload_name}-${var.environment}-defender-ticketing"
}

resource "azurerm_resource_group" "secops" {
  count = local.secops_enabled ? 1 : 0

  name     = local.secops_rg_name
  location = var.location
  tags     = local.default_tags
}

resource "azurerm_logic_app_workflow" "defender_ticketing" {
  count = local.secops_enabled ? 1 : 0

  name                = local.secops_la_name
  location            = azurerm_resource_group.secops[0].location
  resource_group_name = azurerm_resource_group.secops[0].name

  identity {
    type = "SystemAssigned"
  }

  tags = merge(local.default_tags, {
    "secops-role"      = "defender-ticketing"
    "ticketing-target" = var.defender_ticketing_target
  })
}

# HTTP request trigger - its callback URL is the target the Security Center
# automation invokes. The connector action (open GitHub/ADO/ServiceNow ticket)
# is added to this workflow as a follow-up step.
resource "azurerm_logic_app_trigger_http_request" "defender_ticketing" {
  count = local.secops_enabled ? 1 : 0

  name         = "When_a_Defender_alert_is_received"
  logic_app_id = azurerm_logic_app_workflow.defender_ticketing[0].id

  schema = jsonencode({
    type = "object"
    properties = {
      schemaId = { type = "string" }
      data     = { type = "object" }
    }
  })
}

resource "azurerm_security_center_automation" "defender_ticketing" {
  count = local.secops_enabled ? 1 : 0

  name                = local.secops_aut_name
  location            = azurerm_resource_group.secops[0].location
  resource_group_name = azurerm_resource_group.secops[0].name
  scopes              = ["/subscriptions/${var.subscription_id}"]

  action {
    type        = "LogicApp"
    resource_id = azurerm_logic_app_workflow.defender_ticketing[0].id
    trigger_url = azurerm_logic_app_trigger_http_request.defender_ticketing[0].callback_url
  }

  source {
    event_source = "Alerts"

    # Only forward High-severity alerts to keep ticket volume actionable.
    rule_set {
      rule {
        property_path  = "Severity"
        operator       = "Equals"
        expected_value = "High"
        property_type  = "String"
      }
    }
  }

  tags = local.default_tags
}
