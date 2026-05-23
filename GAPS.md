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
- [ ] Add 3rd wizard option `hub_and_spoke`
- [ ] New module: `bootstrap/modules/azure/hub/` (hub VNet + optional Azure Firewall + Route Table)
- [ ] Wizard questions: hub address space, firewall yes/no, firewall SKU (Basic/Standard/Premium)
- [ ] Workload TF consumes freshly-created hub outputs (auto-populates `hub_vnet_resource_id`, etc.)
- [ ] Conditional Firewall policy + rule collection groups
- [ ] Update README/checklist/scenarios doc

---

## B. Step 1 (standalone topology) follow-ups — shipped but not fully proven

- [x] **Cloud test the standalone path** end-to-end: `Deploy-AKSLandingZone` → `terraform apply`. Bootstrap (27 resources) created successfully against sub `029039e3-…` / org `abengtss-max-org` on 2026-05-23. Workload repo + GH Actions environments live. **AKS cluster apply not yet verified** — needs to run the workload `cd.yaml` workflow.
- [ ] Confirm AKS cluster boots and reaches the internet via NAT gateway (no UDR, no peering) — pending workflow run.
- [ ] **NEW** — Fix `terraform init -migrate-state` 403 in bootstrap. The state-migration step fails because the local Azure principal lacks `Storage Blob Data Contributor` on the just-created storage account. Either auto-assign the role inside the bootstrap composition (preferred) or document a manual `az role assignment create` step.
- [ ] Decide & implement standalone-appropriate defaults for AKS — currently `is_corp = false` flips:
  - `outbound_type` → `loadBalancer` (instead of `userDefinedRouting`) ✅ probably correct
  - `private_cluster_enabled` → `false` (public API server) ⚠ may or may not be what we want
  - `private_dns_zone_id` → null ⚠ no private DNS for standalone
  - Consider a new `standalone_private_cluster` flag or document the trade-off explicitly
- [ ] Add Pester test for the wizard topology branch (mock `Read-Host`/`Read-NumberedSelection`, assert `config.connectivity_subscription_id == ""` when standalone)
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

- [ ] **Standalone + `multi_region_*` scenarios**: never tested. `secondary_location` + ACR geo-replication likely still works, but `is_corp = false` may disable things the multi-region scenarios assume.
- [ ] **Preflight validation** in `Test-DeploymentPrerequisites`:
  - [x] Enforce `topology: spoke` ⇒ `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip`, `connectivity_subscription_id` all non-empty
  - [x] Enforce `topology: standalone` ⇒ hub_* and `connectivity_subscription_id` all empty (warn + auto-clear, or fail)
  - [x] Fail fast with a clear error before `terraform init`

---

## E. Security action items (user-only)

- [ ] **Rotate exposed PATs** (3 GitHub PATs were pasted in conversation history; treat as compromised):
  - `github_pat_11AN6XUNQ08NOj5AdrCZtF_…`
  - `github_pat_11AN6XUNQ0KvEIqED43FTF_…`
  - `github_pat_11AN6XUNQ0exOpJ025J9IR_…`
  - [ ] Revoke at https://github.com/settings/tokens
  - [ ] Regenerate, store only in env vars or secret manager going forward

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
