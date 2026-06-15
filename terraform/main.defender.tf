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
# -----------------------------------------------------------------------------
resource "azurerm_security_center_subscription_pricing" "containers" {
  count = var.enable_defender_for_containers_plan ? 1 : 0

  tier          = "Standard"
  resource_type = "Containers"

  extension {
    name = "AgentlessDiscoveryForKubernetes"
  }

  extension {
    name = "ContainerRegistriesVulnerabilityAssessments"
  }
}
