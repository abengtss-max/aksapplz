# Day-2 Operations Runbook

Operational procedures for running `Deploy-AKSLandingZone`-managed clusters
in production. Pairs with [scenarios-and-options.md](scenarios-and-options.md)
and [deployment-checklist.md](deployment-checklist.md).

Last reviewed: 2026-05-23 — applies to `1.4.0-rc1`.

---

## 1. Cluster upgrade

The AKS cluster automatically receives:

- **Kubernetes patch** (`automatic_upgrade_channel = "patch"` in baseline scenarios)
- **Node OS image** (`node_os_upgrade_channel = "NodeImage"`)

Minor-version upgrades (e.g. 1.34 → 1.35) require a manual change to
`kubernetes_version` in `aks-landing-zone.auto.tfvars` followed by a CD run.

```powershell
# Trigger the workload repo's CD pipeline after editing kubernetes_version:
gh workflow run cd.yaml -R <org>/<workload-repo> -f environment=test
```

Always upgrade `test` first, then promote.

## 2. Scaling

### Cluster nodes
- **System pool** is managed by the cluster-autoscaler (`min/max` in tfvars).
- **User pool** scales by HPA + KEDA (if enabled). Tune via tfvars
  `aks_user_pool_min_count` / `aks_user_pool_max_count`.

### App workloads
- Use HPA + KEDA for event-driven scale.
- For long-tail right-sizing, enable VPA (`enable_vpa = true`) — recommended
  for multi-region scenarios (07–10).

## 3. Backup & restore

When `enable_backup = true` (scenarios 04, 05, 06, 07–10, 12):
- Azure Backup for AKS protects PVCs + cluster state.
- Backup vault lives in the workload RG.
- **Restore drill**: every quarter, restore one PVC to a scratch namespace and
  verify the file count. Record the result in the change log.

When `enable_backup = false`, you are responsible for any PV snapshots
(e.g. `velero`, app-level dumps).

## 4. Secret rotation

| Secret | Where | Rotation cadence | Procedure |
|---|---|---|---|
| `TF_VAR_github_personal_access_token` | GHA secret `GH_PAT_LZ` | 90 days | Generate new fine-scoped PAT → update repo secret → re-run last successful CI to verify |
| `TF_VAR_github_runners_personal_access_token` | GHA secret `GH_PAT_RUNNERS` | 90 days | Same as above; only used when `use_self_hosted_runners = true` |
| AKS cluster admin Entra group | tfvars `aks_admin_group_object_ids` | On membership change | Edit tfvars → CD apply |
| Grafana admin group | tfvars `grafana_admin_group_object_id` | On membership change | Edit tfvars → CD apply |
| Key Vault data-plane | Managed identity — no rotation needed | — | — |

## 5. Destroy

As of v1.4.0-rc2 the public cmdlet supports tear-down via `-Action destroy`
(mirroring the upstream `Deploy-Accelerator -Action destroy` pattern):

```powershell
# 1. First, tear down the workload (AKS, spoke VNet, App Gateway, ...) via its CD pipeline
gh workflow run destroy.yaml -R <org>/<workload-repo> -f environment=<env>

# 2. Then destroy the bootstrap (GitHub repo + GHA identities + bootstrap storage) and,
#    for hub_and_spoke topology, the hub composition. Order is handled automatically:
#    spoke-bootstrap first, then hub.
Deploy-AKSLandingZone -Environment <env> -Action destroy
# Or non-interactive:
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action destroy -AutoApprove
```

The cmdlet will prompt for the literal word `destroy` unless `-AutoApprove`
is passed. For `hub_and_spoke` topology the spoke bootstrap is destroyed
first (which deletes the generated workload repo + GHA federated
identities), then the hub composition is destroyed.

> **Order matters.** Step 1 (workload CD `destroy` workflow) must run before
> step 2, otherwise the bootstrap destroy will delete the workflow itself
> before it has had a chance to clean up the spoke Azure resources, leaving
> orphans.

## 6. State recovery

If the bootstrap remote state blob is lost, corrupted, or diverged from
reality (failed apply/destroy, manual rotation gone wrong, accidental
overwrite), recover from a known-good state file using the cmdlet — no need
to import resources one at a time.

```powershell
# Auto-discover: cmdlet looks for an errored.tfstate left behind in the
# bootstrap composition by a failed apply/destroy.
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action import -AutoApprove

# Explicit: pass a known-good state file (e.g. produced by `terraform state pull`
# before the corruption, or a backup downloaded from the storage account).
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action import `
    -StateBackup .\backup.tfstate -AutoApprove
```

The import path:
1. Validates the source JSON has `version`, `terraform_version`, and `resources`.
2. **Always re-discovers** the state RG and storage account for the resolved
   environment — never trusts on-disk `backend.tf`. Errors out cleanly with
   "the backend storage account is gone" if the state RG was wiped.
3. Re-grants `Storage Blob Data Contributor` to the operator (idempotent) with
   a 30s RBAC propagation wait.
4. Re-renders `terraform.tfvars.json` (workspace operations still evaluate
   required variables — `TF_VAR_github_personal_access_token` etc. must be set).
5. Selects the per-env workspace, or creates it if missing.
6. Runs `terraform state push <source>` and post-verifies with
   `terraform state list` (aborts if the remote ends up empty).
7. Auto-removes the local `errored.tfstate` after a successful push.

After recovery, run `Deploy-AKSLandingZone -InputConfigPath … -Action plan`
(or the workload CD pipeline's plan job) to confirm the recovered state
matches Azure, then proceed normally.

**Backup recommendation**: snapshot remote state with `terraform state pull >
backup-$(Get-Date -Format yyyyMMdd-HHmm).tfstate` before any high-risk
operation (provider major-version bump, large refactor, container rotation).

> ⚠ `terraform state push` rejects a source whose `serial` is lower than the
> current remote serial. If you hit this on a serially-bumped corrupted state,
> bump the source file's `serial` field above the remote's and retry, or
> manually `terraform state push -force <source>` from the bootstrap dir.

## 7. Drift detection

CD pipeline includes a nightly `terraform plan` that emails the owners if the
plan is non-empty. Investigate within 24 h.

Typical drift sources:
- Manual edits in the Azure Portal — re-apply via CD to overwrite.
- Out-of-band managed-identity changes — generally safe to re-apply.
- Upstream AVM module updates — pin module versions in `versions.tf` if
  unwanted upgrades are causing drift.

## 8. Incident response

| Symptom | First action | Escalation |
|---|---|---|
| Cluster API unreachable | `az aks show -g <rg> -n <cluster> --query 'powerState'`; check NSG; check NAT GW health | Open Azure support ticket; revert last CD run |
| Pods stuck `ImagePullBackOff` | Check ACR private endpoint + DNS resolution from cluster | Open ACR ticket; verify managed-identity AcrPull role |
| App Gateway 502 | Check backend health probes; verify pod readiness | Roll back deployment; check WAF logs |
| CD pipeline `terraform apply` fails with `ResourceExists` | State drift — see §7 | Manual import per §6 |
| Key Vault access denied from cluster | Verify workload identity federation; check KV access policy | `az aks get-credentials` then `kubectl describe pod`; check token exchange |

## 9. Cost controls

`enable_cost_analysis = true` enables the AKS Cost Analysis add-on. Review
namespace cost weekly in Azure Portal.

Quick wins:
- Set HPA min replicas to 0 + KEDA scale-to-zero where possible.
- Use Spot VMs for non-prod user pools (`vm_size_spot` tfvars override).
- Disable Defender (`enable_defender = false`) in `dev`/`test` envs.
- Use `aks_sku_tier = "Free"` in `dev` (scenario 11 demonstrates this).

## 10. Pre-publish accelerator updates

When publishing accelerator changes that affect generated workload repos:

1. Bump `ModuleVersion` per SemVer + add Prerelease tag if pre-GA.
2. Update `CHANGELOG.md` with `Added` / `Changed` / `Fixed` / `Removed`.
3. Run L1 + L2 locally (see `ALZ.AKS/tests/e2e/`).
4. Run L3 for at least one scenario per topology.
5. Tag the release in git: `git tag v1.4.0-rc1 && git push --tags`.
6. (Future) Publish to PSGallery via `Publish-Module`.
