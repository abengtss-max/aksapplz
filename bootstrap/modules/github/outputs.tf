output "repository_full_name" {
  description = "Full org/repo name of the workload repository."
  value       = github_repository.this.full_name
}

output "repository_html_url" {
  description = "Web URL of the workload repository."
  value       = github_repository.this.html_url
}

output "repository_node_id" {
  description = "GraphQL node ID of the workload repository."
  value       = github_repository.this.node_id
}

output "environment_names" {
  description = "Names of GitHub Actions environments created on the workload repo."
  value       = [for e in github_repository_environment.this : e.environment]
}

output "team_id" {
  description = "Numeric ID of the approver team (null when no team is used)."
  value       = local.team_id
}

output "runner_group_id" {
  description = "Numeric ID of the GitHub Actions runner group (null when not created)."
  value       = try(github_actions_runner_group.this[0].id, null)
}

output "runner_group_name" {
  description = "Name of the GitHub Actions runner group (defaults to 'Default' when not created)."
  value       = try(github_actions_runner_group.this[0].name, "Default")
}
