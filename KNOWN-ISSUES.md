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
| BUG-D | Apply path — state migration on private storage | **Fixed in code (v1.4.1) — regulated cloud verification pending** | The post-apply `terraform init -migrate-state` to the new azurerm backend failed with `403 AuthorizationFailure` because the bootstrap state storage account is created with `publicNetworkAccess: Disabled` and `defaultAction: Deny`, exposing only a **private endpoint** in the workload spoke VNet. The operator running the cmdlet from their workstation could not reach the SA data plane (RBAC granted, no network path). **Fix:** the apply path now records the SA's original `publicNetworkAccess` / `networkRuleSet.defaultAction`, and for regulated state accounts temporarily opens a firewall window (`--public-network-access Enabled --default-action Allow`, 60s settle, one-shot 90s retry on 403) for the migration, then **restores the original posture in a `finally` block** (guarded by `$saNetOpened`). Baseline scenarios (S1, S2, S2.5) are unaffected. **Manual fallback if needed:** `az storage account network-rule add --subscription <sub> -g <state-rg> -n <state-sa> --ip-address <operator-ip>`, rerun `Deploy-AKSLandingZone -Action apply -SkipPreflight`, then remove the rule. |



## Pre-GA limitations (planned for v1.4.0 / v1.5.0)

These items are **not yet implemented** and are tracked in [GAPS.md](GAPS.md) (Section C).
Treat the current release as **preview / release-candidate** if you need any of them.

| Area | Limitation | Workaround | Target |
|---|---|---|---|
| Self-referential teardown leftovers | `-Action destroy` may briefly leave the state RG and identity RG as empty shells because terraform loses access to its own backend mid-destroy when it deletes the state storage account. All resources inside the RGs are destroyed correctly. The destroy path now **verifies and retries** RG deletion (polls up to 3 min, then issues a final synchronous `az group delete --yes`) and reports an ERROR only if an RG is still present (e.g. due to a resource lock). | If an RG persists after the error, check for resource locks then run `az group delete -n <rg> --yes`. | v1.5.0 |
| PSGallery | Module is not published to PowerShell Gallery | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1` from a local clone | v1.4.0 |

## Externally-blocked items (cannot fix in this repo)

| Area | Limitation | Origin |
|---|---|---|
| Log Analytics AVM | `log_analytics` AVM module emits a deprecated `local_authentication_disabled` warning during `terraform plan` | Upstream AVM module — waiting for fix |
| Live multi-region **failover test** in the current dev tenant | The end-to-end failover drill (deploy both regions, then drain/fail the primary and confirm the global LB shifts traffic to the secondary) cannot be exercised in dev tenant `79ee578e`. A Microsoft governance policy `MCAPSGovDenyPolicies → VMSS_LimitNodesCount_Deny (v1.0.0)` is assigned at the management-group / tenant-root scope and inherited by all subscriptions. Its policy rule calls `empty()` on an integer, which errors and **denies all AKS node-pool VMSS creation tenant-wide**, so no cluster nodes can be created. The assignment sits above subscription scope and is not modifiable from these subscriptions. **The Terraform/IaC is validated** (95/97 resources deployed; the only 2 failures were this policy on the primary node pool and an unrelated zone-availability mismatch on the secondary, now fixed via `secondary_availability_zones`). The live failover drill requires either an MCAPS policy exemption for the target RG or a different tenant. | Microsoft MCAPS governance policy (tenant-root scope) |

## Operational caveats

- **First-run cost**: a single `single_region_baseline` standalone apply provisions ~50 Azure resources (AKS, ACR, Key Vault, App Gateway, NAT GW, public IP, NSGs, monitor workspaces). Allow ~$15-30/day at rest if you forget to destroy.
- **Plan-only mode** (`-PlanOnly`) of `Deploy-AKSLandingZone` still requires Azure provider authentication — provider must be able to read existing resources to compute the plan.
- **`hub_and_spoke` topology** keeps hub state as Terraform **local state** (per-env workspace) inside `bootstrap/alz/hub/`. Remote-state migration for the hub composition is pending and tracked in CHANGELOG v1.3.0 "Notes".
- **Azure Firewall Basic SKU** is intentionally not supported in v1.3+. Use Standard or Premium.
- **CD approval gate depends on your GitHub plan (informational, not a defect)**. The CD Apply job always runs against the `apply_environment` GitHub Environment and the module always wires the `apply_approvers` as required reviewers. Whether the manual-approval gate is *enforced* depends on the repo's GitHub plan: GitHub **Team**, **Enterprise**, or **any public repo** enforce environment protection rules, so the approval gate works as intended. On a **Free plan with a private repo**, GitHub does not support environment protection rules, so the reviewers are silently ignored — deployments still succeed, just without a manual gate. To enable the gate, upgrade the org to GitHub Team/Enterprise, make the workload repo public, or add CODEOWNERS + branch protection.

## Known terraform warnings (non-blocking)

| Warning | Source | Status |
|---|---|---|
| `local_authentication_disabled` deprecated in `azurerm_log_analytics_workspace` | upstream `log_analytics` AVM module | external |

## Reporting new issues

- **Bug / regression**: open a GitHub issue with reproduction steps + scenario YAML
- **Security**: see [SECURITY.md](SECURITY.md)
- **Roadmap requests**: comment on [GAPS.md](GAPS.md)
