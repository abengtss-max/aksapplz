# -----------------------------------------------------------------------------
# Region module - Microsoft Sentinel SIEM onboarding (#31)
#
# WAF for AKS (Security): integrate with a security monitoring / SIEM tool.
# Defender for Containers detects threats; Microsoft Sentinel adds the SIEM
# correlation and analytics layer on top of the AKS diagnostic logs already
# shipped to this region's Log Analytics workspace (kube-apiserver, kube-audit /
# kube-audit-admin, guard). Opt-in via var.enable_sentinel (default false,
# cost-aware) so no Sentinel ingestion charges are incurred unless requested.
# -----------------------------------------------------------------------------

variable "enable_sentinel" {
  type    = bool
  default = false
}

# Onboard Microsoft Sentinel onto the shared Log Analytics workspace. Once
# onboarded, Sentinel analytics rules can correlate the AKS audit logs that the
# cluster diagnostic settings already stream to this workspace.
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "main" {
  count = var.enable_sentinel ? 1 : 0

  workspace_id = module.log_analytics.resource_id
}
