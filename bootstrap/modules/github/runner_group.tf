resource "github_actions_runner_group" "this" {
  count                   = local.use_runner_group ? 1 : 0
  name                    = var.runner_group_name
  visibility              = "selected"
  selected_repository_ids = [github_repository.this.repo_id]
}
