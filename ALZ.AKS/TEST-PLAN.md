# ALZ.AKS Module — Comprehensive Test Plan

## 1. Executive Summary

Test every scenario and option combination in the ALZ.AKS module by running the full
bootstrap → CI → CD pipeline end-to-end against real Azure infrastructure.

| Item | Detail |
|------|--------|
| **Module** | ALZ.AKS v1.0.0 |
| **Scenarios** | 4 (single_region_baseline, multi_region_baseline, single_region_regulated, multi_region_regulated) |
| **Option toggles** | 16 feature flags + landing_zone_type |
| **Total tests** | 10 (4 scenario + 6 option-toggle) |
| **Estimated time** | ~5-7 hours (30-45 min per deploy) |
| **Estimated cost** | ~$50-80 (AKS + supporting resources, destroyed after each test) |

---

## 2. Pre-Requisites — Code Fixes Required

During test-plan research, **3 gaps** were found that will block end-to-end testing.
These must be fixed before any test runs.

### Fix 1: Add `landing_zone_type` to tfvars generation

`Write-TfvarsFile` does not output `landing_zone_type`. It defaults to `"corp"` in
`variables.tf`, but the connectivity subscription has **no hub VNet** deployed.
Tests will fail at VNet peering.

**Fix:** Add `landing_zone_type` to `inputs.yaml` schema and `Write-TfvarsFile`.
For testing, all tests use `"online"` mode (no hub dependency).

### Fix 2: Resolve `tenant_id` automatically

`Write-TfvarsFile` hardcodes `tenant_id = "REPLACE_ME"`. The CI/CD pipeline has no
mechanism to replace this. Terraform will accept the literal string but Azure API
calls will fail.

**Fix:** Set `tenant_id` from the Azure CLI context during `Write-TfvarsFile`
(`az account show --query tenantId -o tsv`).

### Fix 3: Resolve `grafana_admin_group_object_id` automatically

Same issue as tenant_id — hardcoded `"REPLACE_ME"`.

**Fix:** Use `aks_admin_group_object_ids[0]` or the current user's object ID as
the default when not explicitly set.

### Fix 4: Add `-Force` parameter for CI/CD automation

`Deploy-AKSLandingZone` prompts `"Proceed with bootstrap? (yes/no)"` via
`Read-Host`. This blocks automated testing.

**Fix:** Add `-Force` switch to skip the confirmation prompt.

---

## 3. Environment

| Resource | Value |
|----------|-------|
| Tenant ID | `11111111-1111-1111-1111-111111111111` |
| AKS Subscription | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` |
| Connectivity Sub | `bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb` |
| Bootstrap Sub | `aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa` (same as AKS) |
| GitHub Org | `abengtss-max-org` |
| User Object ID | `cccccccc-cccc-cccc-cccc-cccccccccccc` |
| Primary Location | `swedencentral` |
| Secondary Location | `westeurope` (multi-region tests) |

---

## 4. Naming Convention for Tests

Each test gets a unique `service_name` + `environment_name` + `postfix_number` to
avoid resource collisions. Tests can run sequentially (deploy → validate → destroy → next).

| Test ID | service_name | env | postfix | Repo Name | RG Name |
|---------|-------------|-----|---------|-----------|---------|
| T01 | `akstest` | `t01` | 1 | `akstest-t01` | `rg-akstest-t01-sc-001` |
| T02 | `akstest` | `t02` | 1 | `akstest-t02` | `rg-akstest-t02-sc-001` |
| T03 | `akstest` | `t03` | 1 | `akstest-t03` | `rg-akstest-t03-sc-001` |
| T04 | `akstest` | `t04` | 1 | `akstest-t04` | `rg-akstest-t04-sc-001` |
| T05 | `akstest` | `t05` | 1 | `akstest-t05` | `rg-akstest-t05-sc-001` |
| T06 | `akstest` | `t06` | 1 | `akstest-t06` | `rg-akstest-t06-sc-001` |
| T07 | `akstest` | `t07` | 1 | `akstest-t07` | `rg-akstest-t07-sc-001` |
| T08 | `akstest` | `t08` | 1 | `akstest-t08` | `rg-akstest-t08-sc-001` |
| T09 | `akstest` | `t09` | 1 | `akstest-t09` | `rg-akstest-t09-sc-001` |
| T10 | `akstest` | `t10` | 1 | `akstest-t10` | `rg-akstest-t10-sc-001` |

---

## 5. Test Matrix

### Tier 1: Scenario Tests (T01–T04)

Each scenario runs with its default feature flags. Validates the core path.

| ID | Scenario | Key Differentiators | Expected Resources |
|----|----------|--------------------|--------------------|
| **T01** | `single_region_baseline` | Standard SKU, Calico, no FIPS, no Istio, no Flux, min_count=2 | VNet, AKS, ACR, KV, Log Analytics, Prometheus, Grafana, App GW |
| **T02** | `multi_region_baseline` | Standard SKU, Calico, Flux=on, VPA=on, Backup=on, ACR Geo-Repl=on | Same as T01 + Flux extension, Backup extension, ACR with geo-replication |
| **T03** | `single_region_regulated` | Premium SKU, Azure NPM, FIPS=on, Istio=on, VPA=on, Backup=on, Cost Analysis=on, min_count=3, PCI label | Same as T01 + Istio mesh, higher HA node counts |
| **T04** | `multi_region_regulated` | Premium SKU, Azure NPM, FIPS+Istio+Flux=on, Geo-Repl=on, min_count=3 | Full feature set: all extensions + geo-replication |

### Tier 2: Option Toggle Tests (T05–T10)

Based on `single_region_baseline`, each test toggles a specific feature to validate
conditional Terraform logic.

| ID | Option Toggled | From → To | What Changes |
|----|---------------|-----------|-------------|
| **T05** | `enable_app_gateway` | `true → false` | App Gateway + WAF + NSG should NOT be created |
| **T06** | `enable_istio` | `false → true` | Istio service mesh enabled, internal gateway created |
| **T07** | `enable_flux` | `false → true` | Flux v2 extension provisioned on AKS |
| **T08** | `enable_defender` + `enable_prometheus` | `true → false` | No Defender profile, no Prometheus DCE/DCR |
| **T09** | `enable_keda` + `enable_vpa` | `keda=true,vpa=false → keda=false,vpa=true` | KEDA off, VPA on |
| **T10** | `landing_zone_type` | `online → corp` | UDR to firewall, VNet peering (requires hub VNet setup) |

> **T10 special setup:** Create a simple hub VNet (`10.0.0.0/22`) in the connectivity
> subscription before running this test to validate Corp/peering logic.

---

## 6. Test Execution Flow (per test)

```
┌─────────────────────────────────────────────────────────┐
│  1. CREATE inputs.yaml for test (unique naming)         │
│  2. RUN Deploy-AKSLandingZone -InputConfigPath -Force   │
│     → Step 1/6: Terraform Backend (SA + RG)             │
│     → Step 2/6: Managed Identity + OIDC federation      │
│     → Step 3/6: GitHub repo + team + environments       │
│     → Step 4/6: Self-Hosted Runner (ACI)                │
│     → Step 5/6: Push Terraform code + tfvars            │
│     → Step 6/6: Push CI/CD template workflows           │
│  3. WAIT for GitHub Actions CI pipeline (terraform plan)│
│  4. APPROVE GitHub Actions CD pipeline if gates active  │
│  5. WAIT for CD pipeline to complete (terraform apply)  │
│  6. VALIDATE Azure resources exist & are correct        │
│  7. UPDATE test-results.md with pass/fail + details     │
│  8. DESTROY: terraform destroy + delete RGs + repos     │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Validation Criteria

For each test, validate:

### 7a. Bootstrap Validation (Steps 1-6)
- [ ] Resource group created in correct subscription/location
- [ ] Storage account created with ZRS, soft delete, versioning
- [ ] Managed identity created with federated credentials for GitHub OIDC
- [ ] GitHub repo created with correct branch protection
- [ ] GitHub environments (plan/apply) created with reviewer gates
- [ ] ACI runner container started and registered with GitHub
- [ ] Terraform code + tfvars pushed to main branch
- [ ] CI/CD workflows pushed to main branch

### 7b. CI Pipeline Validation
- [ ] CI workflow triggered on push to main
- [ ] `terraform init` succeeds (backend configured)
- [ ] `terraform plan` succeeds (no errors)
- [ ] Plan output shows expected resource count

### 7c. CD Pipeline Validation
- [ ] CD workflow triggered after CI success
- [ ] Environment approval gate works (if configured)
- [ ] `terraform apply` succeeds
- [ ] No resources in error state

### 7d. Azure Resource Validation
| Resource | Validation |
|----------|------------|
| Resource Group | Exists in correct subscription/location, tags correct |
| VNet | Correct address space, 6 subnets created, NSGs attached |
| AKS Cluster | Correct SKU, version, network policy, node pool sizes, zones |
| System Node Pool | Correct VM size, min/max counts, ephemeral disk |
| User Node Pool | Correct VM size, min/max counts, labels (incl. PCI if regulated) |
| ACR | Premium, zone redundant, geo-replication (if multi-region) |
| Key Vault | RBAC, purge protection, soft delete |
| Log Analytics | Retention = 90 days |
| Prometheus | DCE + DCR associated with AKS |
| Grafana | Standard SKU, zone redundant |
| App Gateway | WAF v2 Prevention mode (if enabled) |
| Istio | Service mesh profile enabled (if enabled) |
| FIPS | FIPS node pools (if enabled) |
| Flux | Extension installed (if enabled) |
| Backup | Extension installed (if enabled) |

### 7e. Interconnection Validation
- [ ] AKS → ACR: Managed identity has `AcrPull` role
- [ ] AKS → Key Vault: Managed identity has Key Vault access
- [ ] AKS → VNet: System and user pools in correct subnets
- [ ] ACR → Private Endpoint: Connected via PE subnet (if private)
- [ ] VNet → Hub: Peering established (Corp mode only)

---

## 8. Cleanup Strategy

After each test validation:

1. **Terraform Destroy** — Clone repo, run `terraform destroy -auto-approve`
2. **Delete Azure RGs** — Bootstrap RG, AKS managed RGs, network watcher RG
3. **Delete GitHub repos** — `gh repo delete akstest-tXX --yes`
4. **Delete GitHub teams** — `gh api -X DELETE /orgs/{org}/teams/{team}`

Between tests, verify the AKS subscription has no leftover RGs from the
previous test before starting the next one.

---

## 9. Test Inputs Template

Each test generates an `inputs.yaml` with this structure (values vary per test):

```yaml
scenario: "single_region_baseline"
landing_zone_type: "online"          # NEW — required fix
bootstrap_location: "swedencentral"
aks_landing_zone_subscription_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
connectivity_subscription_id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
hub_vnet_resource_id: ""
hub_vnet_name: ""
hub_vnet_resource_group_name: ""
hub_firewall_private_ip: ""
spoke_vnet_address_space: "10.10.0.0/16"
subnet_address_prefix_aks_system_nodes: "10.10.0.0/24"
subnet_address_prefix_aks_user_nodes: "10.10.1.0/22"
subnet_address_prefix_aks_api_server: "10.10.5.0/28"
subnet_address_prefix_app_gateway: "10.10.6.0/24"
subnet_address_prefix_private_endpoints: "10.10.7.0/24"
subnet_address_prefix_ingress: "10.10.8.0/24"
kubernetes_version: "1.31"
aks_sku_tier: "Standard"
aks_private_cluster: false           # false for online mode
aks_admin_group_object_ids:
  - "cccccccc-cccc-cccc-cccc-cccccccccccc"
bootstrap_subscription_id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
service_name: "akstest"
environment_name: "t01"              # varies per test
postfix_number: 1
use_self_hosted_runners: true
use_private_networking: true
github_personal_access_token: "Set via environment variable"
github_runners_personal_access_token: "Set via environment variable"
github_organization_name: "abengtss-max-org"
apply_approvers:
  - "abengtss-max"
# Feature toggles (vary per test)
enable_defender: true
enable_workload_identity: true
enable_azure_policy: true
enable_prometheus: true
enable_grafana: true
enable_app_gateway: true
enable_acr: true
enable_key_vault: true
enable_keda: true
enable_vpa: false
enable_istio: false
enable_nginx_ingress: false
enable_flux: false
enable_dapr: false
enable_fips: false
enable_backup: false
enable_cost_analysis: false
enable_node_auto_provisioning: false
iac_type: "terraform"
bootstrap_module_name: "aksapplz_github"
starter_module_name: "aks_landing_zone"
```

---

## 10. Detailed Per-Test Configuration Deltas

### T01: single_region_baseline (defaults)
No changes from template above.

### T02: multi_region_baseline
```yaml
scenario: "multi_region_baseline"
environment_name: "t02"
secondary_location: "westeurope"
enable_vpa: true
enable_flux: true
enable_backup: true
enable_acr_geo_replication: true
```

### T03: single_region_regulated
```yaml
scenario: "single_region_regulated"
environment_name: "t03"
aks_sku_tier: "Premium"
enable_vpa: true
enable_istio: true
enable_fips: true
enable_backup: true
enable_cost_analysis: true
```

### T04: multi_region_regulated
```yaml
scenario: "multi_region_regulated"
environment_name: "t04"
secondary_location: "westeurope"
aks_sku_tier: "Premium"
enable_vpa: true
enable_istio: true
enable_flux: true
enable_fips: true
enable_backup: true
enable_cost_analysis: true
enable_acr_geo_replication: true
```

### T05: App Gateway disabled
```yaml
environment_name: "t05"
enable_app_gateway: false
```

### T06: Istio enabled on baseline
```yaml
environment_name: "t06"
enable_istio: true
```

### T07: Flux enabled on baseline
```yaml
environment_name: "t07"
enable_flux: true
```

### T08: Monitoring disabled
```yaml
environment_name: "t08"
enable_defender: false
enable_prometheus: false
enable_grafana: false
```

### T09: Scaling swapped
```yaml
environment_name: "t09"
enable_keda: false
enable_vpa: true
```

### T10: Corp mode (hub VNet peering)
```yaml
environment_name: "t10"
landing_zone_type: "corp"
aks_private_cluster: true
hub_vnet_resource_id: "<created during test setup>"
hub_vnet_name: "vnet-hub-test"
hub_vnet_resource_group_name: "rg-hub-test"
hub_firewall_private_ip: "10.0.0.4"
```

---

## 11. Test Results Tracking

A `TEST-RESULTS.md` file will be created and updated after each test with:

| Column | Description |
|--------|-------------|
| Test ID | T01–T10 |
| Scenario | Name |
| Status | ⏳ Pending / ✅ Pass / ❌ Fail / ⚠️ Partial |
| Bootstrap | Pass/Fail + duration |
| CI Pipeline | Pass/Fail + run URL |
| CD Pipeline | Pass/Fail + run URL |
| Resources | Count created / expected |
| Issues | Any errors or warnings |
| Duration | Total time |
| Destroyed | Yes/No |

---

## 12. Execution Order

1. **Apply 4 pre-requisite code fixes** (Section 2)
2. **Clean up existing test resources** (delete prior aksapplz-prod repos/RGs if needed)
3. **Run T01** → validate → record → destroy
4. **Run T02** → validate → record → destroy
5. **Run T03** → validate → record → destroy
6. **Run T04** → validate → record → destroy
7. **Run T05** → validate → record → destroy
8. **Run T06** → validate → record → destroy
9. **Run T07** → validate → record → destroy
10. **Run T08** → validate → record → destroy
11. **Run T09** → validate → record → destroy
12. **Create hub VNet** → **Run T10** → validate → record → destroy hub VNet
13. **Final cleanup** — verify zero leftover resources
14. **Publish final TEST-RESULTS.md**

---

## 13. Risk & Mitigation

| Risk | Mitigation |
|------|-----------|
| AKS deployment timeout (>30 min) | Set pipeline timeout to 60 min |
| ACI runner fails to register | Check ACI logs, retry with fresh container |
| Resource quota limits | Use Standard_D4ds_v5 (common SKU), destroy between tests |
| FIPS node pool restrictions | Some regions/VM sizes don't support FIPS — use swedencentral with D4ds_v5 |
| GitHub API rate limits | Space tests apart, use single PAT |
| Terraform state lock | Ensure clean destroy before next test |
| Cost overrun | Destroy after each test, set budget alerts |
