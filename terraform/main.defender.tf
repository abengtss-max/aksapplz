# -----------------------------------------------------------------------------
# Root - Microsoft Defender for Containers (subscription-wide plan)
#
# enable_defender (per-cluster) turns on the in-cluster security_monitoring
# agent via the AKS security_profile. That alone leaves Defender for Cloud
# reporting "partial" coverage because agentless discovery and registry
# vulnerability assessment are subscription-level capabilities.
#
# This resource raises the SUBSCRIPTION Defender for Containers plan to the
# Standard tier and enables the agentless + registry-scanning extensions, which
# clears the partial-coverage warning and gives full Defender for Cloud
# protection.
#
# WARNING: This is SUBSCRIPTION-WIDE and BILLED. It affects every cluster and
# registry in the subscription, not just this landing zone, and incurs cost
# (per protected vCPU and per scanned image). It is therefore gated behind
# var.enable_defender_for_containers_plan (default false). Removing the flag
# later sets the plan back to Free for the whole subscription.
#
# PRE-FLIGHT CHECK: Microsoft.Security/pricings/Containers is a per-subscription
# SINGLETON that always exists (defaulting to "Free"). Another landing zone, a
# prior deployment, or an Azure Policy may have already raised the whole
# subscription to Standard. In that case the azurerm provider treats the
# existing non-Free pricing as a conflict and fails the ENTIRE apply. To avoid
# that, we read the current tier first and simply leave the plan untouched when
# it is already enabled — only creating it when the subscription is still Free.
# -----------------------------------------------------------------------------
data "azapi_resource" "defender_containers_current" {
  count                  = var.enable_defender_for_containers_plan ? 1 : 0
  type                   = "Microsoft.Security/pricings@2024-01-01"
  resource_id            = "/subscriptions/${var.subscription_id}/providers/Microsoft.Security/pricings/Containers"
  response_export_values = ["properties.pricingTier"]
}

locals {
  # True when the customer opted in but the subscription plan is already on the
  # paid Standard tier, so this landing zone must not try to manage it again.
  defender_containers_already_enabled = var.enable_defender_for_containers_plan && try(
    data.azapi_resource.defender_containers_current[0].output.properties.pricingTier == "Standard",
    false
  )
}

resource "azurerm_security_center_subscription_pricing" "containers" {
  # Only manage the plan when the customer opted in AND it is not already
  # enabled at the subscription level by something outside this landing zone.
  count = var.enable_defender_for_containers_plan && !local.defender_containers_already_enabled ? 1 : 0

  tier          = "Standard"
  resource_type = "Containers"

  extension {
    name = "AgentlessDiscoveryForKubernetes"
  }

  extension {
    name = "ContainerRegistriesVulnerabilityAssessments"
  }
}
