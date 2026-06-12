# -----------------------------------------------------------------------------
# Root - Azure Kubernetes Fleet Manager (opt-in)
# No AVM module exists for Fleet Manager, so native azurerm resources are used.
# When enabled, every regional AKS cluster is auto-joined as a fleet member,
# enabling multi-cluster orchestration (update runs, staged rollouts).
# Ref: https://learn.microsoft.com/azure/kubernetes-fleet/overview
# -----------------------------------------------------------------------------
resource "azurerm_kubernetes_fleet_manager" "main" {
  count = local.enable_fleet ? 1 : 0

  name                = local.fleet_name
  resource_group_name = azurerm_resource_group.global[0].name
  location            = var.location
  tags                = local.default_tags
}

# Join every regional AKS cluster as a fleet member.
resource "azurerm_kubernetes_fleet_member" "region" {
  for_each = local.enable_fleet ? local.regions : {}

  name                  = "member-${each.key}"
  kubernetes_fleet_id   = azurerm_kubernetes_fleet_manager.main[0].id
  kubernetes_cluster_id = module.region[each.key].aks_cluster_id
  group                 = each.key
}
