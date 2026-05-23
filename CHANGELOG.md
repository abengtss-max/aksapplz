# Changelog

All notable changes to the `ALZ.AKS` PowerShell module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
