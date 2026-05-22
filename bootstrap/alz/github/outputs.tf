output "resource_names" {
  description = "Resolved resource names — useful for debugging the rendering."
  value       = module.resource_names.resource_names
}

# Phase 5/6 will add: backend coords, MI client IDs, ACR login server,
# repository URL, runner group ID.
