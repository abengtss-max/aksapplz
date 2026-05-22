resource "github_repository" "this" {
  name                 = var.repository_name
  description          = var.repository_description
  visibility           = "private"
  auto_init            = true
  allow_update_branch  = true
  allow_merge_commit   = false
  allow_rebase_merge   = false
  has_issues           = true
}

resource "github_repository_vulnerability_alerts" "this" {
  repository = github_repository.this.name
  enabled    = true
}

resource "github_branch_protection" "main" {
  count         = local.supports_protected_branches ? 1 : 0
  depends_on    = [github_repository_file.this]
  repository_id = github_repository.this.name
  pattern       = "main"

  enforce_admins                  = true
  required_linear_history         = true
  require_conversation_resolution = true

  required_pull_request_reviews {
    dismiss_stale_reviews           = true
    required_approving_review_count = local.approver_count > 1 ? 1 : 0
  }
}
