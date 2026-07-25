# -----------------------------------------------------------------------------
# Region module - GitOps & Application Platform cluster extensions
# -----------------------------------------------------------------------------
# Flux (GitOps) and Dapr are delivered as AKS cluster extensions rather than
# add-ons on the managed-cluster resource, so they are wired here (opt-in via
# var.enable_flux / var.enable_dapr). Cost Analysis is wired directly on the
# AKS module in aks.tf (metrics_profile.cost_analysis).
# -----------------------------------------------------------------------------

# Flux v2 GitOps extension
resource "azurerm_kubernetes_cluster_extension" "flux" {
  count = var.enable_flux ? 1 : 0

  name           = "flux"
  cluster_id     = module.aks.resource_id
  extension_type = "microsoft.flux"
}

# Dapr (Distributed Application Runtime) extension
resource "azurerm_kubernetes_cluster_extension" "dapr" {
  count = var.enable_dapr ? 1 : 0

  name           = "dapr"
  cluster_id     = module.aks.resource_id
  extension_type = "Microsoft.Dapr"
}
