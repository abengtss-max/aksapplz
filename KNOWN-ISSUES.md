# Known Issues & Limitations

Last reviewed: 2026-06-12 — applies to `1.4.0` GA.

## Live multi-region failover — VALIDATED (2026-06-12)

The end-to-end multi-region failover drill has now been **executed live** in subscription `applz-5`
(`eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee`) across `swedencentral` (primary) + `westeurope` (secondary),
after a temporary, scoped MCAPS policy exclusion was applied to the test subscription and **restored
afterwards**. Result: both AKS clusters (K8s 1.33.12) healthy, fleet members joined, ACR geo-replicated,
both App Gateways serving region-distinct content, and **Azure Front Door priority routing failed over
from primary → secondary when the primary app was taken down, then failed back to primary on restore.**
All ephemeral test resources were destroyed and the MCAPS policy posture was restored.

| ID | Area | Resolution |
|---|---|---|
| BUG-G | App Gateway public IP idempotency | **Fixed.** `azurerm_public_ip.app_gateway` showed a spurious `ip_tags` ForceNew diff on refresh, causing Terraform to try to replace the PIP while it was still attached to the App Gateway (`400 PublicIPAddressCannotBeDeleted`). Added `lifecycle { ignore_changes = [ip_tags] }`. Verified live: re-plan produced 0 destroys. |
| BUG-H | AcrPull role assignment race | **Fixed.** The `aks_acr_pull` role assignment in `modules/region` referenced a deterministic ACR resource id, so it had no dependency on the real ACR resource and could run before the registry existed (`404`). Moved it to root `main.acr.tf` (`for_each = module.region`, `scope = module.acr.resource_id`, `principal_id = each.value.aks_kubelet_identity.objectId`), breaking the region↔acr cycle while preserving a real dependency. Verified live: both AcrPull assignments applied cleanly. |

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
| `multi_region_baseline` | `standalone` | multi | ✅ **GA — supported** | S2.5 8/8; live Front Door failover drill validated 2026-06-12 |
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
| Live multi-region **failover test** in the current dev tenant | **Resolved 2026-06-12.** Previously blocked by `MCAPSGovDenyPolicies → VMSS_LimitNodesCount_Deny (v1.0.0)` (tenant-root scope) which denied all AKS node-pool VMSS creation. With a temporary, scoped policy exclusion on the test subscription (since restored), the full live failover drill was executed successfully — see the **Live multi-region failover — VALIDATED** section at the top of this document. In tenants where the MCAPS policy cannot be excluded, deploying AKS node pools still requires an MCAPS policy exemption for the target subscription/RG or a different tenant. | Microsoft MCAPS governance policy (tenant-root scope) |

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
