# Open Gaps & Work Items

Living checklist of functionality that is missing, partially shipped, or known to be incorrect.
Tick a box when the work item has been merged to `main` **and** verified.

Last reviewed: 2026-05-23
Owner: @abengtss-max

---

## A. Roadmap — features we agreed to build but haven't

### A1. Step 2 — Multi-environment support (dev / test / qa / prod)
- [x] Add `-Environment <name>` parameter to `Deploy-AKSLandingZone` — v1.2.0
- [x] Per-env config files: `config/inputs.<env>.yaml` + `config/aks-landing-zone.<env>.tfvars` — v1.2.0
- [ ] Wizard "deploy another env?" loop after each iteration (deferred — re-invoke cmdlet per env)
- [x] Per-env workload repo naming: `{service}-{env}` — v1.2.0 (locals.tf template)
- [x] Per-env bootstrap state isolation via Terraform workspaces — v1.2.0
- [ ] Doc: README Phase 2 + checklist tab on env strategy

### A2. Step 3 — `hub_and_spoke` (greenfield) topology
- [x] Add 3rd wizard option `hub_and_spoke` — v1.3.0
- [x] New module: `bootstrap/modules/azure_hub/` (hub VNet + AzureFirewallSubnet + optional Azure Firewall, policy, zonal PIP) — v1.3.0
- [x] New composition root: `bootstrap/alz/hub/` (separate state, targets connectivity subscription) — v1.3.0
- [x] Wizard questions: hub address space, firewall yes/no, firewall SKU (Standard/Premium), AzureFirewallSubnet prefix — v1.3.0 (Basic SKU intentionally not supported in v1.3 — requires Mgmt subnet+IP)
- [x] Workload TF consumes freshly-created hub outputs — cmdlet captures `terraform output -json` from hub apply and populates `$config.hub_*` before the spoke render — v1.3.0
- [x] Conditional Firewall policy + (no rule collection groups yet — empty policy ships by default, user adds rules post-deploy) — v1.3.0
- [x] Cloud test the `hub_and_spoke` topology end-to-end — passed 2026-05-23 (hub + spoke bootstrap, CD plan green on GitHub-hosted runner against `abengtss-max-org/aksapplz-hub01`; full destroy verified)
- [x] Update README/checklist/scenarios doc with the new topology and the per-tier prereqs — README.md (§0.3), deployment-checklist.md (Decisions 2.5/3/4b), scenarios-and-options.md (topology note + standalone security table)

---

## B. Step 1 (standalone topology) follow-ups — shipped but not fully proven

- [x] **Cloud test the standalone path** end-to-end: bootstrap (27 resources) created 2026-05-23 against sub `029039e3-…` / org `abengtss-max-org`. Workload CD plan green 2026-05-23 (after fixes below); apply pending verification.
- [x] Confirm AKS cluster boots and reaches the internet via NAT gateway — `gh run 26334915216` ✅ success 2026-05-23; AKS `aks-aksapplz-standalone-swc` Running, k8s 1.34.7, system+user pools 2/2 nodes Succeeded; API server reachable (returns Entra auth challenge); no UDR, no peering — pure NAT egress proven.
- [x] Fix `terraform init -migrate-state` 403 in bootstrap (v1.3.0).
- [x] **NEW (2026-05-23) — Standalone workload CD blockers**: fixed in commit `36f0d55`
  - tfvars rendered to repo root → Terraform working_directory mismatch (now `terraform/aks-landing-zone.auto.tfvars`)
  - `azurerm.connectivity` provider failed with empty `connectivity_subscription_id` (now falls back to `var.subscription_id`)
  - `environment` var validation `{1,8}` blocked `standalone` (now `{1,16}`)
  - Key Vault and Grafana names overflowed 24/23-char limits (now length-safe with sha256 fallback)
- [x] Decide & implement standalone-appropriate defaults for AKS — documented in [scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) "Standalone topology — security defaults & trade-offs" table. Current defaults are dev-friendly (`private_cluster_enabled=false`, open authorized IP ranges, system DNS zone, NAT gateway egress). Production hardening guidance documented; users override via per-env tfvars.
- [x] Add Pester test for the wizard topology branch — [ALZ.AKS/tests/Get-InteractiveInputs.Topology.Tests.ps1](ALZ.AKS/tests/Get-InteractiveInputs.Topology.Tests.ps1) covers standalone, hub_and_spoke, and spoke branches (3/3 passing)
- [x] Update test fixture [ALZ.AKS/akstest-t01/config/inputs.yaml](ALZ.AKS/akstest-t01/config/inputs.yaml) with explicit `topology:` field

---

## C. Productisation & hygiene

- [ ] **PSGallery publication**: add `Publish-Module` script, set up API key, decide on SemVer policy, add `CHANGELOG.md`  *(CHANGELOG added in 1.1.0 — still need publish script + API key)*
- [ ] **azd story**: ship an `azure.yaml` wrapper so `azd up` triggers `Deploy-AKSLandingZone` (or document why we don't)
- [ ] **Idempotency / re-run**: define the upgrade contract for re-running `Deploy-AKSLandingZone` with changed inputs
  - [ ] Decide: does re-render overwrite user edits in the workload repo?
  - [ ] Add `-Refresh` (re-render + git push only) vs `-Apply` (full bootstrap) distinction, or document a single safe-merge story
- [ ] **State recovery**: `Import-AKSLandingZoneState` cmdlet or a documented manual recovery runbook for lost tfstate
- [ ] **Destroy path**: `Remove-AKSLandingZone` cmdlet (drains GitHub repo, runs `terraform destroy`, deletes bootstrap RGs)
- [ ] **Secrets handling**:
  - [ ] Optional Key Vault integration for PATs (`-PatFromKeyVault`)
  - [ ] OIDC-only mode (no PATs at all) using GitHub App or Workload Identity Federation for the GitHub provider

---

## D. Smaller correctness gaps

- [x] **Standalone + `multi_region_*` scenarios** — validated 2026-05-23 via terraform plan in sandbox: `Plan: 49 to add, 0 to change, 0 to destroy`, no errors. ACR `georeplications { location = "westeurope" }` correctly generated. `is_corp=false` properly bypasses private endpoints / UDR / private DNS zone; scenario's `private_cluster_enabled=true` is overridden to `false` by the `local.is_corp` gate in `main.aks.tf` (no broken refs). Cloud apply not run — covered by the existing single_region_baseline + standalone validation (run `26334915216`).
- [ ] **Preflight validation** in `Test-DeploymentPrerequisites`:
  - [x] Enforce `topology: spoke` ⇒ `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip`, `connectivity_subscription_id` all non-empty
  - [x] Enforce `topology: standalone` ⇒ hub_* and `connectivity_subscription_id` all empty (warn + auto-clear, or fail)
  - [x] Fail fast with a clear error before `terraform init`

---

## E. Security action items (user-only)

- [x] **Rotate exposed PATs** — completed 2026-05-23 (LZ + runners PATs regenerated)

---

## F. NEW (2026-05-23) — Enterprise readiness gaps surfaced during standalone CD validation

- [~] **Apply environment lacks approval gate** — `cd-template.yaml` Apply job already uses `environment: ${{ inputs.apply_environment }}`, and bootstrap's [github module](bootstrap/modules/github/environment.tf) wires required reviewers from `apply_approvers`. **However**: GitHub free-plan orgs do NOT support environment protection rules on private repos, so the reviewers block is silently skipped (`supports_protected_branches = plan != "free"`). Confirmed `abengtss-max-org` is on free plan + private repo → reviewers ignored. **Path forward**: upgrade to GitHub Team plan, OR make the repo public, OR add CODEOWNERS + branch-protection (paid only too). Module behavior is correct; documenting the constraint here.
- [~] **Resource name length safety — broader audit needed**. Fixed Key Vault (24), Grafana (23), and added DCE (44) + DCR (64) length-safe handling this session via `length(...) <= max ? full : "<prefix>-<truncated><sha3>"` pattern. Still pending: extract a reusable Terraform module / pre-commit lint to catch new resources that don't follow the pattern. Audited resources today: AKS (63), App Gateway (80), Log Analytics (63), Monitor workspace (63), VNet (64), NSGs (80), Managed Identity (128), Subnets (80), Public IP (80), Route Table (80), WAF (128), ACR (50 alphanumeric) — all safe at current naming envelope (≤80 with name_prefix up to ~55).
- [ ] **`environment` naming convention vs. tag value split**. Long env names break short Azure resource names. Consider introducing a separate `environment_short` var (1-6 chars, used in resource naming) alongside `environment` (full, used in tags/labels).
- [x] **CD state-lock race when multiple commits land quickly** — added `concurrency: { group: cd-<apply_env>-<ref>, cancel-in-progress: false }` to `cd.yaml` (template + local copy). Later runs queue instead of racing for tfstate. (Commit pending.)
- [ ] **Provider deprecation warnings** (surfaced during multi_region+standalone plan validation 2026-05-23) — non-blocking but should be cleaned up before AzureRM v5:
  - `azurerm_application_gateway.enable_http2` → `http2_enabled` (main.appgateway.tf:58)
  - `log_analytics` AVM module emits deprecated `local_authentication_disabled` — wait for upstream module fix

---

## Suggested execution order

1. **D — Validation** (cheap, prevents foot-guns)
2. **B — Test fixture + Pester test** (cheap, locks in the topology contract)
3. **B — Standalone cloud test** (needs an Azure run; reveals whether C-private-cluster behaviour is acceptable)
4. **C — CHANGELOG + SemVer** (cheap, unblocks PSGallery)
5. **A1 — Step 2 multi-env** (largest user-visible win)
6. **A2 — Step 3 hub_and_spoke** (largest scope, biggest TF surface)
7. **C — Remove / Import / Refresh** cmdlets
8. **C — PSGallery publish** (after we're confident)
9. **C — azd wrapper**
10. **C — Key Vault / OIDC-only secrets**

## Tracking

When an item is closed, link the PR / commit next to the checkbox:

```
- [x] Add `-Environment` parameter — abc1234
```
