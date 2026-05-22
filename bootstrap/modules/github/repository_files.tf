resource "github_repository_file" "this" {
  for_each            = var.repository_files
  repository          = github_repository.this.name
  branch              = "main"
  file                = each.key
  content             = each.value
  commit_author       = local.primary_approver != "" ? local.primary_approver : "aksapplz-bootstrap"
  commit_email        = local.default_commit_email
  commit_message      = "chore(bootstrap): add ${each.key} [skip ci]"
  overwrite_on_create = true
}
