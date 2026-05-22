locals {
  apply_key       = "apply"
  enterprise_plan = "enterprise"
  free_plan       = "free"

  approvers      = var.approvers
  approver_count = var.create_team ? length(local.approvers) : (var.existing_team_name == "" ? 0 : length(try(data.github_team.this[0].members, [])))

  team_id = var.create_team ? try(github_team.this[0].id, null) : (var.existing_team_name == "" ? null : try(data.github_team.this[0].id, null))

  primary_approver     = length(local.approvers) > 0 ? local.approvers[0] : ""
  default_commit_email = coalesce(local.primary_approver != "" ? "${local.primary_approver}@users.noreply.github.com" : "", "bootstrap@aksapplz.local")

  use_runner_group = var.use_runner_group && data.github_organization.this.plan == local.enterprise_plan

  # Branch protection on private repos + required-reviewers on environments
  # require a paid plan (Pro/Team/Enterprise). Skip on Free.
  supports_protected_branches = data.github_organization.this.plan != local.free_plan
}
