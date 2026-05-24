# Known Issues & Limitations

Last reviewed: 2026-05-24 — applies to `1.4.0` GA.

## Fixed in v1.4.0 GA (resolved 2026-05-24)

| ID | Area | Resolution |
|---|---|---|
| BUG-B | `refresh` action — hub-and-spoke render path | **Fixed.** Refresh now initialises and reads the hub composition (`bootstrap/alz/hub`) workspace and injects `hub_vnet_resource_id` / `hub_vnet_name` / `hub_vnet_resource_group_name` / `hub_firewall_private_ip` into the rendered `terraform/aks-landing-zone.auto.tfvars` before the targeted apply. Verified on S2 Gate 7 (`render=repo=state=7897B`, no apply↔refresh ping-pong). |
| BUG-E | Drift classifier — empty-repo-file detection | **Fixed.** `Get-WorkloadRepoFileContent` now distinguishes a 404 (`return $null`) from an empty file (`return ""`). Empty managed files that have been hand-edited are now correctly classified as `[hand-edited]` rather than `[add]`. Verified on S2 Gate 4 (`Totals: hand-edited=1, unchanged=12`). |
| BUG-F | `refresh` action — missing drift gate on empty hand-edits | **Fixed as a side effect of BUG-E.** With the classifier returning `hand-edited` for empty files, the existing drift gate in the refresh branch blocks correctly. Verified on S2 Gate 5 (refresh without `-Force` aborts with `ERROR` listing `.gitignore`; repo content stays at 0 bytes). |

## v1.4.0 GA — supported vs preview scenarios

| Scenario | Topology | Region mode | GA status | Notes |
|---|---|---|---|---|
| `single_region_baseline` | `standalone` | single | ✅ **GA — supported** | S1 8/8 |
| `multi_region_baseline` | `standalone` | multi | ✅ **GA — supported** | S2.5 8/8 |
| `single_region_baseline` | `hub_and_spoke` | single | ✅ **GA — supported** | S2 8/8 post-fix |
| `multi_region_baseline` | `hub_and_spoke` | multi | ⚠️ **Tech preview** | S4 not validated for v1.4.0 GA; planned for v1.4.1. |
| `single_region_regulated` | `hub_and_spoke` | single | ⚠️ **Tech preview** | Blocked by BUG-D below. Planned for v1.4.1. |
| `multi_region_regulated` | `hub_and_spoke` | multi | ⚠️ **Tech preview** | Blocked by BUG-D below. Planned for v1.4.1. |

## Known limitations carrying into v1.4.0

| ID | Area | Severity | Description |
|---|---|---|---|
| BUG-D | Apply path — state migration on private storage | **Tech-preview limitation (regulated topologies only)** | The post-apply `terraform init -migrate-state` to the new azurerm backend fails with `403 AuthorizationFailure` because the bootstrap state storage account is created with `publicNetworkAccess: Disabled` and `defaultAction: Deny`, exposing only a **private endpoint** in the workload spoke VNet. The operator running the cmdlet from their workstation cannot reach the SA data plane at all — RBAC is granted correctly (`Storage Blob Data Contributor` on the SA) but there is no network path. Confirmed on S3 (single_region_regulated / hub_and_spoke) Gate 1, 2026-05-24. Baseline scenarios (S1, S2, S2.5) are unaffected because their state SAs allow public access. **Workaround today (manual):** `az storage account network-rule add --subscription <sub> -g <state-rg> -n <state-sa> --ip-address <operator-ip>` then rerun `Deploy-AKSLandingZone -Action apply -SkipPreflight`, then remove the rule after migration succeeds. **Planned fix (v1.4.1):** auto-add the operator's public IP to the SA firewall for the migration window, then revert. |



## Pre-GA limitations (planned for v1.4.0 / v1.5.0)

These items are **not yet implemented** and are tracked in [GAPS.md](GAPS.md) (Section C).
Treat the current release as **preview / release-candidate** if you need any of them.

| Area | Limitation | Workaround | Target |
|---|---|---|---|
| Self-referential teardown leftovers | `-Action destroy` leaves the state RG and identity RG as empty shells because terraform loses access to its own backend mid-destroy when it deletes the state storage account. All resources inside the RGs are destroyed correctly. | Run `az group delete -n rg-<svc>-<env>-state-* --yes --no-wait` and `az group delete -n rg-<svc>-<env>-identity-* --yes --no-wait` after `-Action destroy` completes. | v1.5.0 |
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
