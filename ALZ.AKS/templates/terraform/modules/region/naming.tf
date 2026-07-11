# -----------------------------------------------------------------------------
# Region module - naming randomizers
# Random suffixes for globally-unique resource names that can be blocked by
# soft-deleted resources when regenerated with a deterministic name.
# See locals.tf for how these are consumed.
# -----------------------------------------------------------------------------

# Key Vault: 3-char random suffix keyed on the region name_prefix.
# - First apply: fresh random value.
# - Subsequent re-plans in the same workspace: value preserved via TF state.
# - `terraform destroy` -> next fresh apply: value regenerates, sidestepping
#   the 90-day soft-delete window that MCAPS-governed subscriptions cannot
#   shorten with a manual purge (Microsoft best-practice compliant).
resource "random_string" "kv_suffix" {
  length  = 3
  lower   = true
  upper   = false
  numeric = true
  special = false

  keepers = {
    name_prefix = local.name_prefix
  }
}
