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

  # Serialize cluster-modifying operations. The AVM AKS module performs a
  # post-create agent-pool update (azapi_update_resource.default_agent_pool)
  # that is ordered only on the cluster resource, not the whole module. Without
  # this explicit dependency Terraform installs the extension (a long-running
  # cluster operation) concurrently with that agent-pool PUT, which AKS rejects
  # with 409 EtagMismatch ("Another operation is in progress",
  # PutAgentPool_FailedPrecondition, https://aka.ms/aks/aksoperationpreempted).
  # Depending on the whole module makes the extension wait until every
  # cluster/agent-pool operation has settled.
  depends_on = [module.aks]
}

# Dapr (Distributed Application Runtime) extension
resource "azurerm_kubernetes_cluster_extension" "dapr" {
  count = var.enable_dapr ? 1 : 0

  name           = "dapr"
  cluster_id     = module.aks.resource_id
  extension_type = "Microsoft.Dapr"

  # Wait for the cluster module to settle and for Flux to finish installing so
  # at most one long-running cluster extension operation is in flight at a time
  # (avoids concurrent-operation preemption / EtagMismatch).
  depends_on = [module.aks, azurerm_kubernetes_cluster_extension.flux]
}
