data "github_team" "this" {
  count = var.create_team ? 0 : (var.existing_team_name == "" ? 0 : 1)
  slug  = var.existing_team_name
}

resource "github_team" "this" {
  count       = var.create_team ? 1 : 0
  name        = var.team_name
  description = "Approvers for the AKS landing-zone Terraform apply."
  privacy     = "closed"
}

resource "github_team_membership" "approvers" {
  for_each = var.create_team ? toset(local.approvers) : toset([])
  team_id  = local.team_id
  username = each.value
  role     = "member"
}

resource "github_team_repository" "this" {
  count      = local.team_id == null ? 0 : 1
  team_id    = local.team_id
  repository = github_repository.this.name
  permission = "push"
}
