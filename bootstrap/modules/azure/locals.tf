locals {
  # Convenience aliases pulled from the resolved resource_names map.
  rg_state    = var.resource_names["resource_group_state"]
  rg_identity = var.resource_names["resource_group_identity"]
  rg_network  = var.resource_names["resource_group_network"]
  rg_agents   = var.resource_names["resource_group_agents"]
}
