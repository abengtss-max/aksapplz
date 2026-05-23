# Changelog

All notable changes to the `ALZ.AKS` PowerShell module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0-rc2] - 2026-05-23

API hardening release. Replaces the previously-planned standalone
`Remove-AKSLandingZone` cmdlet with an `-Action` switch on the existing
`Deploy-AKSLandingZone` cmdlet, mirroring the upstream Azure Landing Zone
Accelerator pattern (`Deploy-Accelerator -Action apply|destroy`).

### Added
- **`-Action apply|plan|destroy`** parameter on `Deploy-AKSLandingZone`.
  - `apply` (default) — unchanged behaviour.
  - `plan` — equivalent to legacy `-PlanOnly`.
  - `destroy` — self-contained teardown of the bootstrap (spoke) composition
    followed by the hub composition (when `topology=hub_and_spoke`). Requires
    `-InputConfigPath` or `-Environment` to locate the existing config; prompts
    for the literal word `destroy` unless `-AutoApprove` is passed.
- New examples in the cmdlet help block for `-Action destroy` invocation
  (interactive and non-interactive).

### Changed
- **`-PlanOnly` is now an alias** for `-Action plan` (back-compat preserved).
  Combining `-PlanOnly` with `-Action destroy` is rejected with a clear error.
- **README maturity matrix** — destroy row flipped from "planned" to "shipped",
  pointing at the new `-Action destroy` flow.
- **KNOWN-ISSUES.md** — removed the destroy pre-GA item (now implemented).
- **Day-2 runbook §5** — manual 4-step destroy procedure replaced with the
  one-liner `Deploy-AKSLandingZone -Action destroy`. The "destroy workload
  first via the CD pipeline" guidance is preserved.

### Notes
- The cmdlet only destroys the bootstrap-owned resources (generated GitHub
  repo, GHA federated identities, bootstrap storage account, hub VNet/firewall).
  Spoke Azure resources owned by the workload repo (AKS, App Gateway, NAT GW,
  etc.) must still be destroyed by the workload repo's CD `destroy.yaml`
  workflow first — otherwise the bootstrap-destroy will delete the workflow
  itself before it can clean up those resources.

## [1.4.0-rc1] - 2026-05-23

First release candidate of the v1.4.0 line. Focus is **publish-readiness**:
automated end-to-end test harness, governance files, static-analysis gate,
and documented preview-grade limitations.

### Added
- **End-to-end scenario test harness** under `ALZ.AKS/tests/e2e/` (12 scenarios x 4 levels):
  - **L1 render** (`Scenarios.L1.Tests.ps1`) — 112/204 assertions, ~1.5 s.
  - **L2 terraform plan** (`Scenarios.L2.Tests.ps1`) — 60/60 plans across 12 scenarios in ~13 min.
  - **L3 apply+destroy** (`Scenarios.L3.Tests.ps1`) — gated by `ALZ_AKS_E2E_APPLY=1`; sandbox apply with always-on AfterAll destroy.
  - **L4 wizard end-to-end** (`Scenarios.L4.Tests.ps1`) — gated by `ALZ_AKS_E2E_L4=1`; mirrors repo to sandbox, drives `Deploy-AKSLandingZone -PlanOnly` (default) or `-AutoApprove` (full).
- **Scenario matrix (12)**: 3 topologies (standalone/spoke/hub_and_spoke) x 2 scenarios (baseline/regulated) + 4 multi-region variants + feature-flag minimal + feature-flag maximal.
- **PR gate workflow** `.github/workflows/test-scenarios.yml` — L1 single job + L2 matrix of 12 (OIDC, parallel 6, plan only).
- **L3 / L4 manual workflows** `.github/workflows/test-scenarios-l3.yml` and `test-scenarios-l4.yml` — `workflow_dispatch` with comma-separated or `all` scenario selector, environment-gated.
- **Governance files**: `LICENSE` (MIT), `SECURITY.md`, `KNOWN-ISSUES.md`, `CODE_OF_CONDUCT.md`.
- **Static analysis gate** `.github/workflows/static-analysis.yml` — PSScriptAnalyzer + tfsec + checkov (informational; advisory severities only).

### Changed
- **Module version**: `1.3.0` -> `1.4.0` with `Prerelease = 'rc1'`. Manifest `LicenseUri` / `ProjectUri` corrected to the real repo URL.
- **`.gitignore`** extended for ad-hoc `*.tfvars` and `terraform.tfstate*` at repo root + `bootstrap/alz/hub/*.log` (covers destroy logs).

### Fixed
- Working tree hygiene — removed eight stale `*.log` and `*.tfvars` debug artefacts from prior manual runs.
- **Invalid CIDR in scenario templates**: `templates/scenarios/*.tfvars` shipped `aks_user_nodes = "10.10.1.0/22"`, which Azure rejects with `InvalidCIDRNotation` (a /22 must align on a /22 boundary). Corrected to `10.10.16.0/22` (matches what every e2e YAML already uses). **Surfaced by the new L3 harness on the first real cloud apply** — exactly the class of bug L3 exists to catch. Added `ALZ.AKS/tests/Cidr.Alignment.Tests.ps1` (32 cases, runs in <1 s) so the same class of bug fails at unit-test time before any cloud spend.

### Known limitations (see [KNOWN-ISSUES.md](KNOWN-ISSUES.md))
- **L3 cloud verification**: `01-standalone-baseline` apply (~11 min) + destroy (~10 min) verified on Azure 2026-05-23. Remaining 11 scenarios scheduled before GA.
- L4 wizard automated tests are wired but the first real cloud run is part of the rc1 sign-off; until then treat the wizard apply path as preview.
- Several Section-C items (destroy cmdlet, state recovery, OIDC-only secrets, azd wrapper, PSGallery publish) are deferred to v1.5.0.
- Upstream `log_analytics` AVM module emits a deprecated-arg warning during plan (non-blocking).
- GitHub Free-plan orgs cannot enforce environment reviewer rules on private repos.

## [1.3.0] - 2026-05-23

### Added
- **`hub_and_spoke` topology** (greenfield). When `topology=hub_and_spoke`, `Deploy-AKSLandingZone` now provisions a brand-new hub VNet in the connectivity subscription as a first phase, then runs the existing spoke bootstrap with the freshly-minted hub values wired in automatically — no second invocation, no manual tfvars editing.
  - New Terraform module: `bootstrap/modules/azure_hub/` (resource group + VNet + `AzureFirewallSubnet` + optional Azure Firewall, policy, and zonal public IP).
  - New composition root: `bootstrap/alz/hub/` (separate Terraform state; targets the connectivity subscription).
  - Wizard adds the new topology as a third option, then prompts for `hub_vnet_address_space`, `firewall_subnet_address_prefix`, `deploy_firewall`, and `firewall_sku_tier` (Standard | Premium).
  - Preflight accepts `spoke | standalone | hub_and_spoke` and validates required fields per topology.
  - After hub apply, the cmdlet captures `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip` from `terraform output -json` and populates `$config` so the existing spoke render is unchanged.

### Fixed
- **Remote-state migration 403** (`AuthorizationPermissionMismatch`) during `terraform init -migrate-state`. The cmdlet now grants the signed-in operator *Storage Blob Data Contributor* on the bootstrap storage account it just created and waits 30 s for AAD propagation before running the migration. Idempotent — treats "role already exists" as informational. Closes the v1.2.0 known issue.

### Notes
- Azure Firewall **Basic** SKU is intentionally not supported in v1.3 (it requires a Management subnet + Management IP). Use `Standard` or `Premium`.
- Hub composition uses Terraform local state (per-env workspace) for now; remote-state migration for the hub will follow the same pattern as the spoke in a future release.

## [1.2.0] - 2026-05-23

### Added
- **Multi-environment support** for `Deploy-AKSLandingZone`.
  - New `-Environment <name>` parameter (1-8 lowercase alphanumeric chars).
  - When supplied and `-InputConfigPath` is omitted, the cmdlet resolves `config/inputs.<env>.yaml` automatically; falls through to the wizard if it does not exist.
  - Wizard fallback now writes `config/inputs.<env>.yaml` + `config/aks-landing-zone.<env>.tfvars` when `-Environment` is set.
  - `-Environment` overrides `environment_name` in the loaded config so all resource names stay in sync.
- **Per-environment Terraform state isolation** via Terraform workspaces.
  - After `terraform init`, the cmdlet runs `terraform workspace select <env>` and creates a new workspace on demand. Each environment now has its own `terraform.tfstate.d/<env>/` directory inside `bootstrap/alz/github/`.
- End-to-end cloud test against the **standalone** topology in `swedencentral` (sub `029039e3-…`, org `abengtss-max-org`). 27 bootstrap resources created successfully, workload repo + 2 GitHub Actions environments provisioned.

### Changed
- **Breaking — repo & team naming.** `bootstrap/alz/github/locals.tf` now derives:
  - `version_control_system_repository`  = `{{service_name}}-{{environment_name}}`
  - `version_control_system_team`        = `{{service_name}}-{{environment_name}}-approvers`
  Existing deployments will see a destroy/recreate of the GitHub repo + team on the next apply. Use the v1.1.0 template if you must preserve an existing repo name.
- Banner version string now reads from `$script:ScriptVersion` (no longer hardcoded `1.0.0`).

### Known Issues
- Remote-state migration (`terraform init -migrate-state`) fails with **403 AuthorizationPermissionMismatch** because the local Azure principal does not have *Storage Blob Data Contributor* on the storage account that bootstrap just created. Local state remains authoritative and the bootstrap is still considered successful. Workaround: assign the role to the operator (or to the `apply` MI) and re-run with `-SkipPreflight`. Will be fixed in a follow-up by adding the role assignment to the bootstrap composition.

## [1.1.0] - 2026-05-23

### Added
- **Standalone topology** option for the AKS landing zone.
  - New wizard prompt (Decision 2.5): choose `spoke` (peer to an existing ALZ hub, default) or `standalone` (no hub, NAT gateway egress only).
  - When `standalone` is selected, the wizard skips Decisions 3 (connectivity subscription) and 4 (hub VNet / hub firewall).
  - Workload Terraform now derives the internal `is_corp` flag from `hub_vnet_resource_id != ""`, so the route table, UDR, and spoke↔hub VNet peerings are only created when a hub is configured.
- New `topology` field in `config/inputs.yaml` (defaults to `spoke` for back-compat).
- Excel checklist: new row **Decision 0c — topology** with a dropdown (`spoke` / `standalone`).
- Topology coverage in [README.md](README.md), [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) and [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md).
- Pre-flight validation:
  - Fails fast if `topology` is missing or not one of `spoke` / `standalone`.
  - Enforces all hub_* / `connectivity_subscription_id` fields are set when `topology: spoke`.
  - Auto-clears any leftover hub_* values and warns when `topology: standalone`.

### Changed
- `Deploy-AKSLandingZone` is the only exported cmdlet; the legacy `Invoke-AKSLandingZoneTerraform` name is no longer exported.
- When invoked without `-InputConfigPath`, `Deploy-AKSLandingZone` now runs the interactive wizard by default.

### Notes
- Older `inputs.yaml` files without a `topology` field are still accepted; pre-flight defaults them to `spoke` and emits a warning.

## [1.0.0] - 2026-05-22

### Added
- Initial public version. Single cmdlet `Deploy-AKSLandingZone` renders the `bootstrap/alz/github/` Terraform composition and applies it. End-to-end tested against a spoke landing zone in `swedencentral`.
