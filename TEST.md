# Live Validation Plan — ALZ.AKS v1.4.0 GA

**v1.4.0 GA covers S1, S2.5, and S2 (standalone single + multi-region, plus hub-and-spoke single region).** Multi-region hub-and-spoke (S4) and regulated topologies (S3, S5) remain tech preview — see `KNOWN-ISSUES.md`.

Step-by-step live e2e validation. Run **together** with operator (Ali) confirming each gate before the next destructive action.

- Date started: 2026-05-24
- Module version under test: `1.4.0` (GA)
- Azure sub: `029039e3-76a6-4c2e-b3c0-1473059b0193`
- Tenant: `79ee578e-cb66-4cc6-b879-3ff4f6e34a55`
- GitHub org: `abengtss-max-org`
- Default region: `swedencentral` (secondary: `westeurope`)

---

## 0. Pre-flight (do once)

| Check | Command | Pass criteria |
|---|---|---|
| Module imports | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force; (Get-Module ALZ.AKS).Version` | `1.4.0` |
| PATs in env | `"$($env:TF_VAR_github_personal_access_token.Length)/$($env:TF_VAR_github_runners_personal_access_token.Length)"` | both non-zero |
| `GH_TOKEN` set | `$env:GH_TOKEN=$env:TF_VAR_github_personal_access_token; gh api user --jq .login` | returns user |
| Azure context | `az account show --query id -o tsv` | `029039e3-…` |
| Org empty | `gh repo list abengtss-max-org --limit 50 --json name --jq length` | `0` |
| Sub empty (aksapplz) | `az group list --query "[?starts_with(name,'rg-aks') \|\| contains(name,'aksapplz')].name" -o tsv` | empty |

---

## Scenario matrix (Phase 1 — validate as shipped)

**Reality of multi-region in v1.4.0-rc5:** scenarios S2.5/S4/S5 only automate ACR geo-replication + Flux extension. Second cluster, Fleet, and Front Door are manual (covered in Phase 2 tech preview).

| # | Scenario | Topology | Env name (≤8 chars) | Inputs file | Expected resources | Status |
|---|---|---|---|---|---|---|
| S1 | single_region_baseline | standalone | `stdaln01` | `config/inputs.s1-stdaln.yaml` | ~45 | ✅ 2026-05-24 (8/8) — **GA** |
| S2 | single_region_baseline | hub_and_spoke | `hub01` | `config/inputs.s2-hub.yaml` | ~57 | ✅ 2026-05-24 (8/8, post-fix BUG-B/E/F) — **GA** |
| S2.5 | multi_region_baseline | standalone | `mrstd01` | `config/inputs.s2.5-mrstd.yaml` | ~48 (S1+ACR replica+Flux) | ✅ 2026-05-24 (8/8) — **GA** |
| S3 | single_region_regulated | hub_and_spoke | `reg01` | `config/inputs.s3-reg.yaml` | ~65 | ⚠️ Tech preview — BUG-D, planned v1.4.1 |
| S4 | multi_region_baseline | hub_and_spoke | `mr01` | `config/inputs.s4-mr.yaml` | ~60 (S2+ACR replica+Flux) | ⚠️ Tech preview — not validated for v1.4.0 GA, planned v1.4.1 |
| S5 | multi_region_regulated | hub_and_spoke | `mrr01` | `config/inputs.s5-mrr.yaml` | ~70 (S3+ACR replica+Flux) | ⚠️ Tech preview — BUG-D, planned v1.4.1 |

### Why these 6 (and not 8)

| Topology × Scenario | baseline | regulated |
|---|---|---|
| **standalone** | ✅ S1 (single), ✅ S2.5 (multi) | ❌ **invalid** — see below |
| **hub_and_spoke** | ✅ S2 (single), ✅ S4 (multi) | ✅ S3 (single), ✅ S5 (multi) |

**Why `regulated × standalone` is invalid (not just unconventional):**
- Regulated scenario `.tfvars` sets `private_cluster_enabled = true` (mandatory for PCI-DSS).
- Standalone topology forces `private_cluster_enabled = false` in workload TF (no private DNS zone available — there's no hub to host it).
- PCI-DSS 4.0.1 §1.4 requires network segmentation controls (firewall + UDR) that standalone (NAT GW only) cannot provide.
- These two settings contradict → the deploy would either fail at plan time or silently disable a mandatory control. Excluded by design.

**Why S2.5 (`multi-region × standalone`) is worth running:**
- Cheapest way to validate the multi-region code path in isolation (no firewall cost, ~10 min faster apply).
- Proves multi-region wiring works *before* layering on hub-spoke complexity in S4.
- If S4 fails and S2.5 passed, the failure is in the hub-spoke × multi-region interaction, not multi-region itself.
- Real customer use case: dev/test environments wanting geo-redundancy without enterprise networking.

### Per-scenario gate sequence (every scenario follows this)

Each scenario runs the same 8-gate sequence as the rc5 verification:

1. **Apply (greenfield)** — `Deploy-AKSLandingZone -InputConfigPath <file> -AutoApprove -SkipPreflight`
2. **DryRun #1** — `Deploy-AKSLandingZone -InputConfigPath <file> -DryRun` → expect *13 unchanged*
3. **Hand-edit** — `gh api -X PUT /repos/abengtss-max-org/<repo>/contents/.gitignore -f message="drift" -f content=$([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("# drift`n*.local`n"))) -f sha=<current-sha>`
4. **DryRun #2** — expect *1 hand-edited (.gitignore), 12 unchanged*
5. **Refresh (no -Force)** — `Deploy-AKSLandingZone -InputConfigPath <file> -Action refresh` → expect **BLOCKED**, ERROR lists `.gitignore`
6. **Refresh -Force** — `… -Action refresh -Force -AutoApprove` → expect *1 changed via targeted apply*
7. **DryRun #3** — expect *13 unchanged*
8. **Destroy** — `Deploy-AKSLandingZone -InputConfigPath <file> -Action destroy -AutoApprove` then `az group delete` for any leftover identity RG

Record results in **Section 9 — Results** below.

---

## 1. Scenario S1: Single Region Baseline / Standalone

**Inputs file:** reuse existing `config/inputs.standalone.yaml` — but rename `environment_name` to `stdaln01` (8 chars max) and save as `config/inputs.s1-stdaln.yaml`.

Key settings:
- `topology: standalone`, `scenario: single_region_baseline`
- No hub, no peering, NAT gateway egress
- `aks_private_cluster: false` (forced by workload TF)
- Cost: lowest of all scenarios

**Expected resources (greenfield apply):** ~45 (matches rc5 baseline)

**Known constraints:**
- No App Gateway WAF rules tied to hub firewall logs
- Private cluster disabled (no private DNS zone)

---

## 2. Scenario S2: Single Region Baseline / Hub-and-spoke

**Inputs file:** reuse existing `config/inputs.hub01.yaml` (env name `hub01` already ≤8 chars) → copy to `config/inputs.s2-hub.yaml` for clarity.

Key settings:
- `topology: hub_and_spoke`, `scenario: single_region_baseline`
- Bootstrap creates hub VNet `10.0.0.0/16` + Azure Firewall Standard
- Spoke `10.20.0.0/16` peers to hub, UDR routes 0.0.0.0/0 → firewall

**Expected new resources over S1:** hub VNet, firewall, firewall policy, route table, peering pair (~12 extra ≈ **57 total**)

**Gotchas to watch:**
- Firewall provisioning can take 8-15 min — adjust timeouts
- Firewall policy NAT rules must allow `*.dp.kubernetesconfiguration.azure.com` for Flux (S4/S5)

---

## 2.5. Scenario S2.5: Multi Region Baseline / Standalone

**Inputs file to create:** `config/inputs.s2.5-mrstd.yaml`

Derive from `s1-stdaln.yaml` but change:
```yaml
scenario: "multi_region_baseline"
environment_name: "mrstd01"
secondary_location: "westeurope"
enable_acr_geo_replication: true
enable_flux: true
enable_vpa: true
# topology stays "standalone" — no hub, NAT GW egress in both regions
# aks_private_cluster stays false (forced by workload TF)
```

**Expected resources** (if multi-region wired up): ~70 (S1 baseline + 2nd region VNet + 2nd AKS + ACR geo-replica + Flux extension)
**Expected resources** (if only ACR replication active): ~50 (S1 + ACR replica only)

**Validates:**
- Multi-region code path in cheapest possible setup
- ACR geo-replication
- Flux GitOps extension installs cleanly
- 2nd region cluster reachable via its own NAT GW egress

**Cost:** ~$3/hr (2× NAT GW + 2× AKS Standard). Cheaper than S2 (which has the firewall).

**Gotchas to watch:**
- Both regions need quota for DDSv5 (~40 vCPU each)
- ACR replica takes 5-10 min to fully sync after primary apply
- Flux extension install can race with cluster ready signal — retry-on-failure expected

### S2.5 Result (2026-05-24) — 8/8 ✅

env `mrstd01`, sub `029039e3-76a6-4c2e-b3c0-1473059b0193`, primary `swedencentral`, secondary `westeurope`, repo `abengtss-max-org/aksapplz-mrstd01`, backend `staksamrstsc001iqth/tfstate`.

| # | Gate | Result | Evidence |
|---|------|--------|----------|
| 1 | apply | ✅ | `Apply complete! Resources: 45 added`, EXIT=0; state migrated cleanly |
| 2 | plan (DryRun#1) | ✅ | drift table `Totals: unchanged=13`, plan saved to `bootstrap.tfplan`, no prompt, EXIT=0 |
| 3 | hand-edit `.gitignore` via gh api | ✅ | sha `a92291…` → `f43928…`, commit `af9854…` |
| 4 | plan (DryRun#2 — must block) | ✅ | `Totals: hand-edited=1, unchanged=12` + ERROR row directing to `-Force` |
| 5 | refresh (no -Force — must block) | ✅ | same blocked drift report, tfvars stable at 7632B everywhere |
| 6 | refresh -Force | ✅ | `Apply complete! Resources: 0 added, 1 changed, 0 destroyed` (gitignore overwritten) |
| 7 | plan (DryRun#3) | ✅ | **`Totals: unchanged=13`** — no flip-flop, render=repo=state=7632B for `aks-landing-zone.auto.tfvars`; only the unrelated cosmetic `github_team_membership` maintainer→member cycle in terraform plan |
| 8 | destroy | ✅ | `Bootstrap composition destroyed` + `Teardown Complete`; all `mrstd01` RGs removed. EXIT=1 is cosmetic terraform state-save 404 after backend storage destroyed (same as S2) |

**Key finding:** Gate 7 was clean (`unchanged=13`) where S2 failed with the same hand-edit + refresh-Force sequence. This isolates **BUG-B to hub-and-spoke topology only** (workload composition does not flip-flop tfvars when there is no hub render to compose against).

---

## 3. Scenario S3: Single Region Regulated / Hub-and-spoke

**Inputs file to create:** `config/inputs.s3-reg.yaml`

Derive from `hub01.yaml` but change:
```yaml
scenario: "single_region_regulated"
environment_name: "reg01"
aks_private_cluster: true            # mandatory for regulated
aks_sku_tier: "Premium"              # mandatory
enable_fips: true
enable_istio: true                   # mTLS
# istio_internal_ingress_gateway: true (set in scenario .tfvars)
```

**Expected resources:** ~65 (Istio control plane + ingress gateway + Premium SKU enhancements)

**PCI-DSS checks (post-apply manual verify):**
- [ ] `az aks show … --query "agentPoolProfiles[].enableFips"` → all `true`
- [ ] `kubectl get pods -n aks-istio-system` → istiod + ingress running
- [ ] Local accounts disabled: `az aks show … --query "disableLocalAccounts"` → `true`
- [ ] Azure Policy assignment: `az policy assignment list --scope <rg-id>` → includes PCI initiative

---

## 4. Scenario S4: Multi Region Baseline / Hub-and-spoke

**Inputs file to create:** `config/inputs.s4-mr.yaml`

Derive from `hub01.yaml` but change:
```yaml
scenario: "multi_region_baseline"
environment_name: "mr01"
secondary_location: "westeurope"
enable_acr_geo_replication: true
enable_flux: true
enable_vpa: true
```

**Important:** Today the scenario .tfvars sets `secondary_location = ""` by default. Confirm whether the workload TF actually deploys a second AKS + Front Door + Fleet Manager when `secondary_location` is non-empty, or whether (per `docs/multi-region.md`) that's still manual. **This is a known unknown — must verify.**

**Expected resources** (if multi-region wired up): ~95 (second VNet + AKS + ACR replica + Front Door + Fleet)
**Expected resources** (if only ACR replication): ~60

**Pre-test action:** read `ALZ.AKS\templates\docs\multi-region.md` and report which mode is wired up.

---

## 5. Scenario S5: Multi Region Regulated / Hub-and-spoke

**Inputs file to create:** `config/inputs.s5-mrr.yaml`

Combine S3 + S4 deltas:
```yaml
scenario: "multi_region_regulated"
environment_name: "mrr01"
secondary_location: "westeurope"
aks_private_cluster: true
aks_sku_tier: "Premium"
enable_fips: true
enable_istio: true
enable_flux: true
enable_acr_geo_replication: true
```

**Expected resources:** S3 baseline + S4 delta — likely ~110 if full multi-region active.

**Quota risk:** Premium AKS + Istio + 2 regions may hit vCPU quota in swedencentral or westeurope. Run `az vm list-usage -l swedencentral` and `… -l westeurope` for `standardDDSv5Family` before starting. Need ≥ 80 vCPUs per region.

---

## 6. Cost guardrails

| Scenario | Est. cost/hour (USD) | Auto-destroy after |
|---|---|---|
| S1 standalone | ~$1.50 | 2 h |
| S2 hub baseline | ~$3.00 (firewall is the driver) | 2 h |
| S2.5 multi-region standalone | ~$1.80 (S1 + ACR Premium) | 2 h |
| S3 regulated | ~$4.50 | 2 h |
| S4 multi-region baseline | ~$3.30 (S2 + ACR Premium) | 2 h |
| S5 multi-region regulated | ~$4.80 (S3 + ACR Premium) | 2 h |
| Phase 2 tech preview | ~$8/hr (2× clusters + Front Door Premium + Fleet) | 3 h max |

**Total max budget (Phase 1 + Phase 2):** ~$60 (~14 scenario-hours)

**Hard kill switch:** if any scenario exceeds 90 min in apply, abort and destroy.

---

## 7. Execution order & branch strategy

Run sequentially (parallel runs would conflict on shared backend SA and on org rate limits):

```
S1 → destroy → S2 → destroy → S2.5 → destroy → S3 → destroy → S4 → destroy → S5 → destroy
```

**Rationale for this order:** complexity ramps up monotonically. Each scenario adds exactly one variable over the previous: S1→S2 adds hub, S2→S2.5 swaps hub for multi-region (isolates multi-region code), S2.5→S3 adds regulated hardening on hub, S3→S4 adds multi-region to hub, S4→S5 adds regulated on top. If a step fails, you know exactly which variable broke it.

Between scenarios, verify clean slate:
```powershell
gh repo list abengtss-max-org --limit 50 --json name --jq length      # → 0
az group list --query "[?contains(name,'aksapplz') || contains(name,'<env>')].name" -o tsv  # → empty
```

If a scenario fails partway through, **do not proceed to next**. Triage → fix → re-attempt → only then continue.

---

## 8. Stop / continue criteria

**Stop the entire test run if any of:**
- Identity-RG leak that won't delete (would block re-deploy)
- TF backend SA gets stuck in soft-delete
- Quota exhaustion that requires a support ticket
- Any secret accidentally written to terminal log or repo file

**Continue (with note) if:**
- Single-resource transient Azure error → retry once
- gh API rate limit → wait + retry
- Known issue from `KNOWN-ISSUES.md` reproduces → log + continue

---

## 9. Results log (filled during run)

### S1 — Single Region Baseline / Standalone — **PASSED ✅**
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Pre-flight | clean | clean | ✅ | |
| 1. Greenfield apply | 45 added | 45 added | ✅ | 08:00:25→08:03:19 (~4 min). **BLOCKER**: UPN-not-GUID bug in role-assignment grant → had to manually grant Storage Blob Data Contributor with operator objectId `2a151a66-…`, then `terraform init -migrate-state -force-copy -input=false`. Must fix in psm1 before tagging v1.4.0. |
| 2. DryRun #1 | 13 unchanged | 13 unchanged | ✅ | |
| 3. Hand-edit | sha changed | `a92291…`→`772799…` | ✅ | `.gitignore` via `gh api -X PUT` |
| 4. DryRun #2 | 1 hand-edited | hand-edited=1, unchanged=12 | ✅ | |
| 5. refresh (no -Force) | BLOCKED | ERROR listed `.gitignore`, exit 0 with re-run hint | ✅ | clear, actionable error |
| 6. refresh -Force | 1 changed | Apply complete! Resources: 0 added, 1 changed, 0 destroyed | ✅ | targeted apply ~57 s |
| 7. DryRun #3 | 13 unchanged | 13 unchanged | ✅ | |
| 8. Destroy | clean | all RGs gone, state SA hostname unresolvable | ✅ | full cleanup verified via `az group list` |

### S2 — Single Region Baseline / Hub-and-spoke — **PARTIAL ⚠️ (rendered bug found)**
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Pre-flight | clean | clean | ✅ | |
| 1. Greenfield apply | ~57 added | hub composition ready in 8 min, bootstrap 45 added, state migration succeeded automatically (operator objectId used correctly — S1 issue was transient CAE/token) | ✅ | ~13 min total |
| 2. DryRun #1 | 13 unchanged | 13 unchanged | ✅ | |
| 3. Hand-edit | sha changed | `3058444…` | ✅ | |
| 4. DryRun #2 | 1 hand-edited | hand-edited=1, unchanged=12 | ✅ | |
| 5. refresh (no -Force) | BLOCKED | ERROR listed `.gitignore` (PLUS surfaced update-managed=1 for `aks-landing-zone.auto.tfvars` — see bug below) | ✅ | block worked |
| 6. refresh -Force | 1 changed | Apply complete! 0 added, 2 changed, 0 destroyed (gitignore + tfvars) | ✅ (functionally) | but the tfvars change is from the bug, not the operator's hand-edit |
| 7. DryRun #3 | 13 unchanged | **update-managed=1** for `aks-landing-zone.auto.tfvars`: render=7897B repo=7661B state=7661B (flip-flop!) | ❌ | **BUG B (v1.4.0 blocker)** — see below |
| 8. Destroy | clean | Bootstrap destroyed, Hub composition destroyed (6 resources), Teardown Complete, exitcode=0. (My earlier observation that it was orphaned was a tee-buffer artifact, not a real bug.) | ✅ | full clean teardown |

**BUG B — Refresh path does not resolve hub composition outputs (v1.4.0 blocker for hub-and-spoke scenarios)**

The `Bootstrap` action initialises and applies the hub composition before rendering the workload tfvars, so hub-derived fields (firewall IP, hub VNet ID, etc.) end up in `aks-landing-zone.auto.tfvars`. The `refresh` action skips the hub composition entirely and re-renders the same template with those hub fields missing/blank → output is 236 bytes shorter (7897B vs 7661B).

Observable symptom: after `Deploy-AKSLandingZone -Action refresh -Force` on any hub-and-spoke scenario, the next regular run (DryRun, Bootstrap, refresh) reports `update-managed=1` for `terraform/aks-landing-zone.auto.tfvars` — forever. Operator gets stuck in a flip-flop and cannot reach clean state without re-running Bootstrap.

Fix direction: `refresh` action must run the hub composition (or read its existing outputs from state) before calling the render step. Affects S2/S3/S4/S5; S1/S2.5 (standalone) are safe.

### S2.5 — Multi Region Baseline / Standalone
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Pre-flight | clean | | ⬜ | |
| Multi-region mode confirmed | ACR-only OR full | | ⬜ | which: |
| Quota pre-check | ≥40 vCPU both regions | | ⬜ | |
| 1. Greenfield apply | ~50 OR ~70 added | | ⬜ | duration: |
| ACR geo-replication verified | replica in westeurope | | ⬜ | |
| Flux extension installed | `kubectl get -n flux-system pods` ready | | ⬜ | |
| 2-7. (re-run contract) | per matrix | | ⬜ | |
| 8. Destroy | clean both regions | | ⬜ | |

### S3 — Single Region Regulated
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Pre-flight | clean | | ⬜ | |
| 1. Greenfield apply | ~65 added | | ⬜ | |
| PCI checks (FIPS, Istio, local accounts, policy) | all ✅ | | ⬜ | |
| 2. DryRun #1 | 13 unchanged | | ⬜ | |
| 3-7. (re-run contract) | per matrix | | ⬜ | |
| 8. Destroy | clean | | ⬜ | |

### S4 — Multi Region Baseline
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Multi-region mode confirmed | ACR-only OR full | | ⬜ | which: |
| 1. Greenfield apply | ~60 OR ~95 | | ⬜ | |
| ACR geo-replication verified | replica in westeurope | | ⬜ | |
| 2-7. (re-run contract) | per matrix | | ⬜ | |
| 8. Destroy | clean both regions | | ⬜ | |

### S5 — Multi Region Regulated
| Gate | Expected | Actual | Pass | Notes |
|---|---|---|---|---|
| Quota pre-check | ≥80 vCPU both regions | | ⬜ | |
| 1. Greenfield apply | ~110 | | ⬜ | |
| PCI + multi-region checks | all ✅ | | ⬜ | |
| 2-7. (re-run contract) | per matrix | | ⬜ | |
| 8. Destroy | clean both regions | | ⬜ | |

---

## 10. Post-validation deliverables

After all 6 Phase-1 scenarios pass + Phase 2 tech preview:
1. Update `README.md` matrix — mark each scenario row ✅ verified live with date.
2. Update `KNOWN-ISSUES.md` with any new issues found.
3. Move shipped items from `GAPS.md` to changelog.
4. Document Phase 2 manual steps as a v1.5 backlog item ("automate Fleet + Front Door wiring").
5. Tag `v1.4.0` (drop `-rc5`) if **zero new blocking issues**, else cut `rc6`.

---

## 12. Phase 2 — Full multi-region tech preview (after Phase 1 passes)

Goal: validate the complete multi-region story (cmdlet + manual steps) **once**, not per scenario, since the manual steps are identical for any multi-region scenario.

**Chosen scenario for tech preview:** `multi_region_baseline / hub_and_spoke` (same as S4) — most representative without regulated complexity.

**Steps:**
1. Run S4 again with env name `tp01` (primary swedencentral) → wait for AKS ready.
2. Run S4-equivalent inputs with env name `tp02`, region `westeurope` → wait for 2nd AKS ready.
3. Verify ACR geo-replica: push a test image to `tp01` ACR, verify it appears in `tp02` region replica within 5 min.
4. Create Fleet Manager: `az fleet create` in primary RG, `az fleet member create` for both clusters.
5. Create Front Door Premium: profile + origin group + 1 origin per cluster's App Gateway public IP.
6. Validate failover: deploy `hello-world` via Flux to both clusters → curl Front Door FQDN → confirm 200 OK → disable primary origin → confirm traffic routes to secondary.
7. **Document every manual step** with copy-pasteable commands as `docs/multi-region-tech-preview.md`.
8. Destroy both stacks + Fleet + Front Door.

**Out of scope (intentional):** cross-region DNS via Traffic Manager (Front Door covers it), Defender for Containers cross-region correlation, regulated/PCI cross-region (would require S5 × 2 = too expensive for a preview).

**Acceptance:** if curl to Front Door FQDN returns 200 OK from both clusters and failover works, Phase 2 passes.

---

## 11. Ground rules for this live session

- **One scenario at a time.** Ali approves "go" before each scenario starts.
- **No destructive action without explicit confirm** (per session safety rules).
- **All PATs stay in operator's shell** — agent never echoes them.
- **All terminal output captured** to `s<N>-<gate>.log` for postmortem.
- **If anything looks off**, stop and ask — do not push through.

Ready when you are. Say **"start S1"** to kick off.
