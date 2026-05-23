# Known Issues & Limitations

Last reviewed: 2026-05-23 — applies to `1.4.0-rc1`.

## Pre-GA limitations (planned for v1.4.0 / v1.5.0)

These items are **not yet implemented** and are tracked in [GAPS.md](GAPS.md) (Section C).
Treat the current release as **preview / release-candidate** if you need any of them.

| Area | Limitation | Workaround | Target |
|---|---|---|---|
| Destroy | No `Remove-AKSLandingZone` cmdlet | Manual `terraform destroy` in `bootstrap/alz/github/` + `bootstrap/alz/hub/` + delete the generated workload repo | v1.4.0 |
| State recovery | No `Import-AKSLandingZoneState` cmdlet | Manual `terraform import` against the Storage account backend | v1.5.0 |
| Re-run contract | `Deploy-AKSLandingZone` re-render behaviour on existing repos is undocumented | Don't re-run with changed inputs against a populated env; manually reconcile | v1.4.0 |
| Secrets — PAT-less | OIDC-only mode for the GitHub provider is not supported (Terraform `github` provider still needs a PAT) | Provide a fine-scoped PAT via `TF_VAR_github_personal_access_token` | v1.5.0 |
| Secrets — Key Vault | No `-PatFromKeyVault` switch for retrieving PATs from Key Vault at run-time | Pre-export PATs into shell env vars before invoking the wizard | v1.5.0 |
| `azd` integration | No `azure.yaml` wrapper for `azd up` | Use `Deploy-AKSLandingZone` directly | v1.5.0 |
| PSGallery | Module is not published to PowerShell Gallery | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1` from a local clone | v1.4.0 |

## Externally-blocked items (cannot fix in this repo)

| Area | Limitation | Origin |
|---|---|---|
| Log Analytics AVM | `log_analytics` AVM module emits a deprecated `local_authentication_disabled` warning during `terraform plan` | Upstream AVM module — waiting for fix |
| GitHub environment reviewers | GitHub Free-plan orgs cannot enforce reviewer protection rules on private repos. The `apply_approvers` wiring is silently dropped. | GitHub plan limitation. **Workaround**: upgrade the org to GitHub Team, OR make the workload repo public, OR enforce review via CODEOWNERS + branch protection (also paid). |

## Operational caveats

- **First-run cost**: a single `single_region_baseline` standalone apply provisions ~50 Azure resources (AKS, ACR, Key Vault, App Gateway, NAT GW, public IP, NSGs, monitor workspaces). Allow ~$15-30/day at rest if you forget to destroy.
- **Plan-only mode** (`-PlanOnly`) of `Deploy-AKSLandingZone` still requires Azure provider authentication — provider must be able to read existing resources to compute the plan.
- **`hub_and_spoke` topology** keeps hub state as Terraform **local state** (per-env workspace) inside `bootstrap/alz/hub/`. Remote-state migration for the hub composition is pending and tracked in CHANGELOG v1.3.0 "Notes".
- **Azure Firewall Basic SKU** is intentionally not supported in v1.3+. Use Standard or Premium.

## Known terraform warnings (non-blocking)

| Warning | Source | Status |
|---|---|---|
| `local_authentication_disabled` deprecated in `azurerm_log_analytics_workspace` | upstream `log_analytics` AVM module | external |

## Reporting new issues

- **Bug / regression**: open a GitHub issue with reproduction steps + scenario YAML
- **Security**: see [SECURITY.md](SECURITY.md)
- **Roadmap requests**: comment on [GAPS.md](GAPS.md)
