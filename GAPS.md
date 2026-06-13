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
- [x] Wizard "deploy another env?" loop after each iteration — appended a prompt to `Deploy-AKSLandingZone` success path (`ALZ.AKS.psm1`) that re-invokes the cmdlet with `-Environment <next>` until the user presses Enter. Skipped under `-AutoApprove`/`-PlanOnly`.
- [x] Per-env workload repo naming: `{service}-{env}` — v1.2.0 (locals.tf template)
- [x] Per-env bootstrap state isolation via Terraform workspaces — v1.2.0
- [x] Doc: README Phase 2 + checklist tab on env strategy — added "Multi-environment strategy" subsection under Phase 2 (commands, naming tip for `environment_short`, scope table).

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
- [x] **azd story**: shipped a thin `azure.yaml` wrapper at repo root with a `preprovision` hook (pwsh, interactive) that imports `ALZ.AKS/ALZ.AKS.psd1` and runs `Deploy-AKSLandingZone`, plus a no-op `infra/main.tf` shim so `azd up` works. Documented the launcher approach and why azd isn't the primary model in [scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) "Using azd".
- [x] **Idempotency / re-run**: contract defined and enforced in v1.4.0-rc5. Re-render overwrites managed files (`terraform/*.tf`, `.github/workflows/{ci,cd}.yaml`, `terraform/aks-landing-zone.auto.tfvars`, `.gitignore`) by design; operator hand-edits to those paths are detected and block the re-run unless `-Force` is passed. `-Action refresh` ships as the templates-only path (`terraform apply -target=module.github.github_repository_file.this`). `-DryRun` previews drift without touching anything. See README "Re-run contract" and day2-runbook §7.
  - [x] Decide: does re-render overwrite user edits in the workload repo?  *(answer: yes, by design — with safety gate)*
  - [x] Add `-Refresh` (re-render + push only) vs `-Apply` (full bootstrap) distinction  *(shipped as `-Action refresh`)*
- [x] **State recovery**: `-Action import` on `Deploy-AKSLandingZone` (v1.4.0-rc4) pushes a known-good state file to the remote backend; auto-discovers `errored.tfstate` or accepts explicit `-StateBackup <path>`
- [x] **Destroy path**: `-Action destroy` on `Deploy-AKSLandingZone` (v1.4.0-rc3) drains GitHub repo + GHA identities, runs `terraform destroy`, deletes bootstrap RGs (state and identity RG shells remain empty due to self-referential teardown — documented in KNOWN-ISSUES)
- [x] **Secrets handling**:
  - [x] Optional Key Vault integration for PATs (`-PatFromKeyVault`) — added `-PatFromKeyVault <vaultName>` with `-PatSecretName`/`-RunnerPatSecretName`; resolves secrets to `TF_VAR_github_personal_access_token` / `TF_VAR_github_runners_personal_access_token` via `Resolve-KeyVaultPats`
  - [x] OIDC-only mode (no PATs at all) using GitHub App or Workload Identity Federation for the GitHub provider — added `-OidcOnly`; clears PAT TF_VARs, validates GitHub App env (`GITHUB_APP_ID`/`_INSTALLATION_ID`/`_PEM_FILE`) or `GH_TOKEN`/`GITHUB_TOKEN`, and the `github` provider now uses conditional `token` + `dynamic "app_auth"`

---

## D. Smaller correctness gaps

- [x] **Standalone + `multi_region_*` scenarios** — validated 2026-05-23 via terraform plan in sandbox: `Plan: 49 to add, 0 to change, 0 to destroy`, no errors. ACR `georeplications { location = "westeurope" }` correctly generated. `is_corp=false` properly bypasses private endpoints / UDR / private DNS zone; scenario's `private_cluster_enabled=true` is overridden to `false` by the `local.is_corp` gate in `main.aks.tf` (no broken refs). Cloud apply not run — covered by the existing single_region_baseline + standalone validation (run `26334915216`).
- [x] **Preflight validation** in `Test-DeploymentPrerequisites`:
  - [x] Enforce `topology: spoke` ⇒ `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip`, `connectivity_subscription_id` all non-empty
  - [x] Enforce `topology: standalone` ⇒ hub_* and `connectivity_subscription_id` all empty (warn + auto-clear, or fail)
  - [x] Fail fast with a clear error before `terraform init`

---

## E. Security action items (user-only)

- [x] **Rotate exposed PATs** — completed 2026-05-23 (LZ + runners PATs regenerated)

---

## F. NEW (2026-05-23) — Enterprise readiness gaps surfaced during standalone CD validation

- [~] **Apply environment lacks approval gate** — `cd-template.yaml` Apply job already uses `environment: ${{ inputs.apply_environment }}`, and bootstrap's [github module](bootstrap/modules/github/environment.tf) wires required reviewers from `apply_approvers`. **However**: GitHub free-plan orgs do NOT support environment protection rules on private repos, so the reviewers block is silently skipped (`supports_protected_branches = plan != "free"`). Confirmed `abengtss-max-org` is on free plan + private repo → reviewers ignored. **Path forward**: upgrade to GitHub Team plan, OR make the repo public, OR add CODEOWNERS + branch-protection (paid only too). Module behavior is correct; documenting the constraint here.
- [x] **Resource name length safety — broader audit needed**. Fixed Key Vault (24), Grafana (23), and added DCE (44) + DCR (64) length-safe handling this session via `length(...) <= max ? full : "<prefix>-<truncated><sha3>"` pattern. Regression test added: [ALZ.AKS/tests/Naming.Lengths.Tests.ps1](ALZ.AKS/tests/Naming.Lengths.Tests.ps1) (18/18 passing) asserts the pattern is preserved across both `terraform/locals.tf` and `ALZ.AKS/templates/terraform/locals.tf`. Audited resources: AKS (63), App Gateway (80), Log Analytics (63), Monitor workspace (63), VNet (64), NSGs (80), Managed Identity (128), Subnets (80), Public IP (80), Route Table (80), WAF (128), ACR (50 alphanumeric) — all safe at current naming envelope (≤80 with name_prefix up to ~55).
- [x] **`environment` naming convention vs. tag value split** — added optional `environment_short` var (1-6 lowercase alphanumeric, validated). `locals.tf` resolves `env_short = environment_short != "" ? environment_short : environment`, and `name_prefix` + `acr_name` now use `env_short` while `default_tags` keep the full `environment`. Sandbox plan verified: empty `environment_short` ⇒ existing names (`rg-<wl>-standalone-swc`) unchanged; `environment_short="stnd"` ⇒ names compact to `rg-<wl>-stnd-swc` with tag still showing `environment=standalone`. Commit `c638d93`.
- [x] **CD state-lock race when multiple commits land quickly** — added `concurrency: { group: cd-<apply_env>-<ref>, cancel-in-progress: false }` to `cd.yaml` (template + local copy). Later runs queue instead of racing for tfstate. (Commit pending.)
- [~] **Provider deprecation warnings** (surfaced during multi_region+standalone plan validation 2026-05-23) — non-blocking but should be cleaned up before AzureRM v5:
  - [x] `azurerm_application_gateway.enable_http2` → `http2_enabled` (main.appgateway.tf:58)
  - [ ] `log_analytics` AVM module emits deprecated `local_authentication_disabled` — wait for upstream module fix

---

## G. NEW (2026-06-13) — Regulated (PCI-DSS 4.0.1) alignment with MS Learn reference

Verified our `single_region_regulated` / `multi_region_regulated` scenarios against the Microsoft
Learn reference: [pci-intro](https://learn.microsoft.com/azure/aks/pci-intro) →
[pci-ra-code-assets](https://learn.microsoft.com/azure/aks/pci-ra-code-assets). The reference is a
hub-spoke topology with the AKS cluster in a CDE spoke and a second spoke for SRE image-build / jump-box access.

> **Caveat (from the doc):** the MS reference itself is *not* certified — *"deploying the code assets,
> you don't clear audit for PCI DSS 4.0.1. Acquire compliance attestations from a third-party QSA."*
> Our **tech-preview / not-GA-validated** warning on the scenarios page is the correct posture and must stay.

### G1. Controls we already match ✅ (verified in code)
- [x] Hub-spoke with **Azure Firewall** egress + Bastion + on-prem gateway in hub — `hub_and_spoke` topology
- [x] **Private** AKS cluster (API server not public) — `private_cluster_enabled = true` + VNet integration ([aks.tf](terraform/modules/region/aks.tf))
- [x] **App Gateway + WAF v2** with public frontend — `enable_app_gateway = true`
- [x] **Network policy** segmentation — `network_policy = "azure"`
- [x] **mTLS pod-to-pod via service mesh** — Istio, internal ingress gateway (MS uses OSM/Nginx; ingress+mesh are explicitly swappable per the doc)
- [x] **FIPS 140-2** nodes on both pools — `enable_fips = true`
- [x] **Entra ID only**, local accounts disabled — `enable_azure_rbac` + `disable_local_accounts = true`
- [x] **Defender for Containers** — `enable_defender = true`
- [x] **Azure Policy** add-on — `enable_azure_policy = true`
- [x] **Log Analytics 90-day retention** — `log_retention_days` default = 90 ([variables.tf](terraform/variables.tf))
- [x] Managed Prometheus + Grafana + diagnostic settings
- [x] **Azure Backup** for PVCs — `enable_backup = true` (backup extension)
- [x] **Key Vault** + CSI secret rotation (2m)
- [x] System + user node pools on **dedicated subnets**
- [x] **Image cleaner** — `enable_image_cleaner = true`

### G2. Genuine gaps ⚠️ (where we drift from the reference — TODO)
- [ ] **Two user node pools** segmenting in-scope vs out-of-scope workloads via taints/labels. We deploy **one** user pool today. *Medium — this is the core PCI in-scope/out-of-scope segmentation pattern.* Needs: 2nd `agent_pools` entry + taints + `subnet_address_prefixes` for a 2nd user subnet + scenario tfvars.
- [ ] **Encryption-at-host** (host-based encryption). No `enable_host_encryption` variable exists; AVM `default_agent_pool`/`agent_pools` need the flag wired. *Medium — MS recommends + enforce via Policy.*
- [ ] **Customer-managed keys (BYOK)** for OS/data disks (`disk_encryption_set`) **and ACR CMK encryption**. Currently service-managed keys only. *Medium.*
- [ ] **DDoS Network Protection** on the App Gateway public-IP VNet. Not deployed. *Low/Medium — the doc flags the public-IP subnet as in-scope.*
- [ ] **SRE access spoke**: Azure Image Builder + jump-box VMSS in a second spoke for governed `kubectl`/Flux access. Not deployed. *Low — operational, often customer-specific; document as out-of-scope-by-design with guidance.*
- [ ] **Key Vault hybrid Private Link** model (private endpoint + public access for App Gateway TLS-cert integration). `private_endpoints` subnet exists; verify the KV access model end-to-end for the regulated path. *Verify.*
- [ ] **Build agents out-of-scope**: doc requires build/release agents to have no direct cluster API access (push to ACR only, deploy via GitOps). Confirm our CI/CD identity scope matches this. *Verify — likely already true via OIDC + Flux.*

### G3. Doc tasks (this section's track)
- [x] Write up this gap analysis (this section) — 2026-06-13
- [x] Update the **Regulated** section of [scenarios.md](docs/get-started/scenarios.md) to state what we actually deliver and honestly flag G2 deltas as roadmap items — 2026-06-13
- [x] Add the regulated **architecture diagram** to scenarios.md once generated (M365) — `docs/assets/arch-regulated.png` (as-deployed: Firewall-only hub, no jump-box/Image Builder spoke), white card, `../../assets/` — 2026-06-13

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
