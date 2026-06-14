# Changelog

All notable changes to the `ALZ.AKS` PowerShell module are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **`enable_agc` (Application Gateway for Containers)** — a new regional ingress
  option alongside `enable_app_gateway`. When enabled, Terraform provisions a
  dedicated delegated subnet (delegated to
  `Microsoft.ServiceNetworking/trafficControllers`) plus its NSG in every region
  (`agc` key added to `subnet_address_prefixes` /
  `secondary_subnet_address_prefixes`, default `10.10.24.0/24` / `10.20.24.0/24`).
  Follows the "managed by ALB Controller" model: the in-cluster ALB Controller
  (which you install separately) creates and manages the AGC `trafficControllers`
  resource and associates it with the subnet — Terraform provisions the network
  infrastructure only. The delegated subnet ID is surfaced via the new
  `agc_subnet_id` (primary) and `agc_subnet_ids` (per-region map) outputs. The
  interactive wizard exposes an `Enable Application Gateway for Containers (ALB)
  subnet?` toggle (default `false`) and an `agc` subnet prefix prompt.
- **`-PatFromKeyVault <vaultName>`** on `Deploy-AKSLandingZone` (with
  `-PatSecretName` / `-RunnerPatSecretName`, defaulting to `github-pat` /
  `github-runners-pat`) — resolves GitHub PATs from an Azure Key Vault at
  run-time into `TF_VAR_github_personal_access_token` and
  `TF_VAR_github_runners_personal_access_token` via the new
  `Resolve-KeyVaultPats` helper. Values are masked in logs.
- **`-OidcOnly`** on `Deploy-AKSLandingZone` — PAT-less mode for the GitHub
  provider. Clears the PAT `TF_VAR`s and validates either GitHub App
  credentials (`GITHUB_APP_ID`, `GITHUB_APP_INSTALLATION_ID`,
  `GITHUB_APP_PEM_FILE` → `TF_VAR_github_app_*`) or a `GH_TOKEN` /
  `GITHUB_TOKEN` environment token. The wizard skips its PAT prompts in this
  mode. The bootstrap `github` provider now uses a conditional `token` plus a
  `dynamic "app_auth"` block, with new `github_app_id`,
  `github_app_installation_id`, `github_app_pem_file` variables.
  `-PatFromKeyVault` and `-OidcOnly` are mutually exclusive.
- **`azd` wrapper** — a thin `azure.yaml` at the repo root with a
  `preprovision` hook (pwsh, interactive) that imports `ALZ.AKS.psd1` and runs
  `Deploy-AKSLandingZone`, plus a no-op `infra/main.tf` shim so `azd up` works.
  See `ALZ.AKS/docs/scenarios-and-options.md` ("Using azd").

### Fixed
- **Multi-region App Gateway public IP idempotency** — `azurerm_public_ip.app_gateway`
  exhibited a spurious `ip_tags` ForceNew diff on refresh, causing Terraform to
  attempt to replace the public IP while it was still attached to the App
  Gateway (`400 PublicIPAddressCannotBeDeleted`). Added
  `lifecycle { ignore_changes = [ip_tags] }`. Discovered and fixed during the
  live multi-region failover drill (2026-06-12).
- **AcrPull role-assignment race** — the per-region `aks_acr_pull` role
  assignment referenced a deterministic ACR resource id, so it had no
  dependency on the actual ACR resource and could be created before the
  registry existed (`404`). Moved the assignment to root `main.acr.tf`
  (`for_each = module.region`, scoped to `module.acr.resource_id`, principal =
  each region's kubelet identity), which preserves a real dependency and breaks
  the region↔acr cycle. Discovered and fixed during the live multi-region
  failover drill (2026-06-12).
- **BUG-D (state migration on private storage)** — the apply path's
  post-apply `terraform init -migrate-state` no longer fails with
  `403 AuthorizationFailure` on regulated topologies whose bootstrap state
  storage account is private (`publicNetworkAccess: Disabled`,
  `defaultAction: Deny`). The cmdlet now records the SA's original network
  posture, opens a temporary firewall window for the migration (60s settle,
  one-shot 90s retry on 403), and **restores the original posture in a
  `finally` block**. Regulated cloud verification still pending.
- **Destroy path — orphaned RG shells** — `-Action destroy` now verifies and
  retries deletion of the state and identity resource groups (polls up to
  3 min, then a final synchronous `az group delete --yes`) and reports an
  ERROR only if an RG is still present (e.g. a resource lock), instead of
  leaving the fire-and-forget `--no-wait` deletions unverified.

## [1.5.3] - 2026-06-14

### Fixed
- **Wizard — stopped prompting for the unused L7 ingress subnet.** The
  interactive wizard asked for both `subnet_address_prefix_app_gateway` and
  `subnet_address_prefix_agc` during networking (Decision 5), before the ingress
  option was even chosen (Decision 11). It now prompts only for the subnet of the
  ingress actually selected (Application Gateway WAF *or* App Gateway for
  Containers); the unused key keeps its default so the rendered tfvars stays
  valid. Matches the Terraform behaviour, which only creates the subnet whose
  `enable_*` flag is set.
- **Terraform — fixed invalid `moved` block for `aks_acr_pull`.** `moved.tf`
  tried to relocate `azurerm_role_assignment.aks_acr_pull` into
  `module.region["primary"]`, but that role assignment is intentionally kept at
  the root module (`for_each = module.region`) to avoid a region↔ACR dependency
  cycle. `terraform plan` failed with *"Moved object still exists."* The block
  now re-keys the existing instance into `azurerm_role_assignment.aks_acr_pull["primary"]`
  — the correct state migration after adding `for_each` (no destroy/recreate).

## [1.5.2] - 2026-06-14

### Fixed
- **CI/CD — generated workload repo is now self-contained; CD no longer fails
  with "workflow was not found".** The bootstrap creates only the workload repo,
  but its generated `ci.yaml` / `cd.yaml` referenced reusable workflows in a
  separate `<service>-templates` repo that the Terraform path never created
  (and which is restricted on free org plans). The workload repo now ships its
  own `ci-template.yaml` / `cd-template.yaml` and the caller workflows reference
  them locally (`uses: ./.github/workflows/<name>-template.yaml`), removing the
  cross-repo dependency entirely.
- **CI/CD — `cd-template.yaml` referenced variables the bootstrap never set.**
  It read `secrets.ARM_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` and
  `vars.BACKEND_RESOURCE_GROUP/STORAGE_ACCOUNT/CONTAINER/KEY`, none of which
  Terraform provisions. It now uses the same convention as the (working) CI
  template: `vars.AZURE_CLIENT_ID/TENANT_ID/SUBSCRIPTION_ID` for OIDC auth and
  `vars.BACKEND_AZURE_RESOURCE_GROUP_NAME/_STORAGE_ACCOUNT_NAME/`
  `_STORAGE_ACCOUNT_CONTAINER_NAME` for backend init, plus new `runner_label`
  (default `self-hosted`) and `backend_key` (default `aks-landing-zone.tfstate`)
  inputs so plan/apply share state and honour the runner choice.

## [1.5.1] - 2026-06-14

### Fixed
- **Release packaging — bootstrap composition was missing from the install
  zip.** The release workflow zipped only `./ALZ.AKS`, so `install.ps1`
  extracted a version cache (`~/.alz-aks/<version>/`) without the Terraform
  bootstrap. `Deploy-AKSLandingZone` then failed at apply time with
  `Bootstrap root not found: …\<version>\bootstrap\alz\github`. The workflow now
  bundles `./bootstrap` alongside the module, so the composition (and its
  `modules/azure`, `modules/github`, `modules/resource_names`) ships in the
  release and resolves automatically — no full-repo clone required. Only
  git-tracked files are packaged, so no local state, logs, or rendered tfvars
  leak into the asset.

## [1.4.0] - 2026-05-24

GA release. Builds on rc5 with three fixes from live E2E validation and
ships standalone (single + multi-region) and hub-and-spoke (single region)
as supported topologies. Regulated and multi-region hub-and-spoke remain
tech preview — see `KNOWN-ISSUES.md`.

### Fixed
- **BUG-B (data loss, hub-and-spoke)** — `Deploy-AKSLandingZone -Action refresh`
  on a `hub_and_spoke` deployment no longer pushes a tfvars file with empty
  `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`,
  and `hub_firewall_private_ip` values. The refresh path now initialises the
  hub composition workspace and reads its outputs before re-rendering the
  workload tfvars, exactly as the apply path does. Eliminates the
  apply↔refresh content ping-pong of `terraform/aks-landing-zone.auto.tfvars`.
- **BUG-E (silent drift-bypass)** — `Get-WorkloadRepoFileContent` now
  distinguishes a 404 from an empty file (`size: 0`). An empty managed file
  that the operator hand-edited is classified as `[hand-edited]` instead of
  `[add]`, which routes it through the hand-edit safety gate.
- **BUG-F (refresh drift gate)** — resolved as a side effect of BUG-E. With
  empty hand-edited files correctly classified as `hand-edited`, the existing
  drift gate in the refresh path blocks the run and prints the affected
  filenames unless `-Force` is supplied.

### Validation
- S1 (single_region_baseline / standalone) — 8/8 gates pass.
- S2 (single_region_baseline / hub_and_spoke) — 8/8 gates pass post-fix.
- S2.5 (multi_region_baseline / standalone) — 8/8 gates pass.

### Known limitations (deferred to v1.4.1+)
- Multi-region hub-and-spoke (S4) — tech preview only. Not in GA validation
  matrix for v1.4.0.
- Regulated scenarios (S3, S5) — blocked by BUG-D (private-endpoint state
  storage account not reachable from operator workstation). Tech preview.

## [1.4.0-rc5] - 2026-05-23

### Added
- **Re-run contract is now defined and enforced.** Previously, re-running
  `Deploy-AKSLandingZone -Action apply` against an existing env would silently
  overwrite any operator hand-edits to the rendered files in the workload repo
  (`terraform/*.tf`, `.github/workflows/{ci,cd}.yaml`, `terraform/aks-landing-zone.auto.tfvars`,
  `.gitignore`). The behaviour was undocumented and unsafe.

- **`-DryRun` switch** (valid with `-Action apply` and `-Action refresh`).
  Renders templates locally, fetches the current workload-repo content via
  `gh api`, and prints a per-file drift report classifying each managed file
  as `add` / `unchanged` / `update-managed` / `hand-edited`. Exits before
  touching terraform or the repo. Use to preview what a re-run would do.

- **`-Action refresh`**. Re-renders templates + tfvars and pushes only the
  managed files to the workload repo via
  `terraform apply -target=module.github.github_repository_file.this`.
  Skips Entra app, federated creds, state SA, and RBAC bootstrap (those are
  idempotent on a full apply but add several minutes per re-run). Requires a
  previously-applied env. Honours `-DryRun` and `-Force`.

- **`-Force` switch** (valid with `-Action apply|refresh`). Overrides the
  hand-edit safety check so a re-run can intentionally discard operator edits.

- **Hand-edit safety check.** Before `terraform apply` runs on an existing
  env, the cmdlet compares the current workload-repo content against
  terraform state for each `github_repository_file.this[<path>]` entry.
  If any file's repo content differs from state (operator edited it directly),
  the apply is blocked with an error listing the divergent files and the
  remediation: either move the edits into `ALZ.AKS/templates/` and re-run
  without `-Force`, or re-run with `-Force` to overwrite the operator edits.
  Greenfield applies skip this check (state map is empty, every file is an `add`).

### Changed
- `-Action` parameter accepts a new value: `'refresh'`. Validation messages
  for `-StateBackup`, `-DryRun`, and `-Force` updated to reflect the expanded
  action set.
- Help text for `Deploy-AKSLandingZone` expanded to document the re-run
  contract, the four file-status classifications, and which paths in the
  workload repo are managed vs operator-owned.

### Documentation
- README adds a **Re-run contract** section listing managed file paths,
  what `-Action apply` / `refresh` does on a re-run, the hand-edit policy,
  and a worked example of `-DryRun` + `-Action refresh`.
- `ALZ.AKS/docs/day2-runbook.md` adds §7 "Re-run contract" covering all
  four file-status classifications and the operator workflow for safe
  template changes.
- `KNOWN-ISSUES.md` removes the obsolete "Re-run contract" pre-GA row.
- `GAPS.md` §C marks idempotency / re-run contract items as shipped.

### Verified
- Param validation tests (rc5: 4/4 new guards passing).
- Full live cycle on `swedencentral` standalone env: greenfield apply →
  `-DryRun` shows 0 diffs → operator edit via `gh api` → `-DryRun` shows
  1 `hand-edited` → `-Action refresh` (no `-Force`) blocked correctly →
  `-Action refresh -Force` reconciles → `-DryRun` shows 0 diffs again →
  destroy clean.

## [1.4.0-rc4] - 2026-05-23

State recovery feature: when the remote terraform state in the bootstrap
backend gets corrupted, deleted, or otherwise diverges from reality, you can
now repair it without leaving the cmdlet.

### Added
- `-Action import` on `Deploy-AKSLandingZone`. Pushes a known-good terraform
  state file to the remote azurerm backend for the resolved environment. No
  new cmdlet — same single entry point.
- `-StateBackup <path>` parameter. Explicit path to the source state file to
  push. Only valid with `-Action import`. When omitted, the cmdlet auto-
  discovers an `errored.tfstate` left behind in the bootstrap composition by
  a failed apply or destroy.
- Always re-discovers the state RG and storage account on import (never trusts
  on-disk `backend.tf`), then re-grants `Storage Blob Data Contributor` to the
  operator with a 30s propagation wait — same self-heal shape proven in the
  rc3 destroy path. Falls through to a clear "the backend storage account is
  gone" error when the state RG truly doesn't exist anymore.
- Pre-push validation: the source file must parse as JSON and contain
  `version`, `terraform_version`, and `resources` before any backend mutation.
- Post-push verification: aborts with an explicit error if `terraform state
  list` returns zero after the push.
- Workspace handling: selects the per-env workspace if it exists, creates it
  if it doesn't (the whole point of recovery is to repopulate state).
- Auto-cleans the local `errored.tfstate` after a successful push so the file
  doesn't get re-picked-up on a future run.

### Verified
End-to-end on `swedencentral` against the standalone topology:
1. Fresh apply → 45 resources, state migrated to azurerm backend (serial 48).
2. `terraform state pull` → captured 32-resource good state (49 instances).
3. Uploaded an empty serial-1 state to the remote blob via `az storage blob
   upload --overwrite`, breaking the prior stale lease first. Confirmed
   `terraform state list` returned 0 (remote corrupted).
4. `Deploy-AKSLandingZone -Action import -StateBackup good.tfstate -AutoApprove
   -SkipPreflight` → discovered state SA, granted RBAC, init, workspace select,
   pushed state, post-verify reported 49 instances restored, banner printed.
5. `Deploy-AKSLandingZone -Action destroy -AutoApprove -SkipPreflight` against
   the recovered state → workload repo destroyed, all 45 resources inside the
   state and identity RGs destroyed (only empty RG shells remained — same rc3
   self-referential-teardown limitation, not introduced by rc4).

### Parameter validation tests (all passing)
- `-StateBackup` with `-Action apply` → errors fast.
- `-Action import` with no source and no `errored.tfstate` → errors with
  remediation hint.
- `-Action import -StateBackup nonexistent.tfstate` → errors with "does not
  exist".
- `-Action import -StateBackup junk.txt` (non-JSON) → errors with JSON parse
  message.

## [1.4.0-rc3] - 2026-05-23

Bug-fix release for the `-Action destroy` path discovered during real-cloud
end-to-end validation. The rc2 destroy command went through the motions but
could silently report success without actually destroying anything; rc3 makes
the destroy path honest and recovers from terraform's self-referential
backend-teardown.

### Fixed
- **`-Action destroy` now renders `terraform.tfvars.json` before invoking
  `terraform destroy`.** rc2 skipped the render entirely on destroy, which
  caused terraform to fail with `Error: No value for required variable` (the
  PATs and `repository_files` map are still evaluated during destroy).
- **`-Action destroy` no longer reports false-positive success when the target
  workspace is missing.** rc2 logged a warning and fell through to destroy
  whatever workspace happened to be active (typically `default`, which
  contained nothing) and then printed the "Teardown Complete" banner. rc3
  hard-aborts with a clear error if the per-env workspace is not present.
- **`-Action destroy` aborts cleanly when the workspace state has zero
  tracked resources** instead of running a no-op destroy and claiming success.
- **`-Action destroy` recognises terraform's self-referential teardown error
  (404 / "Failed to persist state to backend" / "Error releasing the state
  lock") and treats it as a successful destroy.** This is expected when the
  bootstrap composition manages its own remote state storage account: after
  the SA is destroyed, terraform cannot save final state back to it and
  returns a non-zero exit code, even though every tracked resource was
  destroyed.
- **`-Action destroy` self-heals an operator missing `Storage Blob Data
  Contributor` on the remote state SA** (idempotent grant + 30 s propagation
  sleep) when the destroy is invoked from a different machine than the one
  that ran apply.
- **`-Action destroy` self-heals a stale `backend.tf` on disk** that points
  at a different environment's storage account, by re-discovering the target
  env's state RG + SA from Azure and rewriting the file before init.

### Verified end-to-end (real cloud, swedencentral, `aksapplz-standalone`)
- Fresh apply → 45 resources created; state migrated to fresh remote SA.
- `-Action destroy -AutoApprove` → all 45 resources destroyed (incl. workload
  GitHub repo, federated identities, managed identities, both bootstrap RGs).
  Self-referential teardown error correctly classified as expected success.

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
