resource "github_repository_environment" "this" {
  depends_on  = [github_team_repository.this]
  for_each    = var.environments
  repository  = github_repository.this.name
  environment = each.key
  wait_timer  = each.value.wait_timer

  dynamic "reviewers" {
    for_each = each.key == local.apply_key && local.team_id != null && local.approver_count > 0 && local.supports_protected_branches ? [1] : []
    content {
      teams = [local.team_id]
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = each.key == local.apply_key && local.supports_protected_branches ? [1] : []
    content {
      protected_branches     = true
      custom_branch_policies = false
    }
  }
}
