# Advanced Guide

For end users who have already followed [QUICKSTART.md](QUICKSTART.md) and want the full reference: scenarios, all cmdlet parameters, the re-run contract, multi-environment patterns, state recovery, and troubleshooting.

---

## Scenarios

`scenario` in `inputs.yaml` selects a pre-defined option bundle. Each scenario maps to a `.tfvars` file under [ALZ.AKS/templates/scenarios/](ALZ.AKS/templates/scenarios/) that the cmdlet merges with your `inputs.yaml`.

| Scenario | GA status | What it enables |
|---|---|---|
| `single_region_baseline` | ✅ **GA** (standalone + hub_and_spoke) | Defender for Containers, Workload Identity, NAT egress (standalone) or firewall egress (hub-and-spoke). |
| `multi_region_baseline` | ✅ **GA** (standalone only) — ⚠️ tech preview for hub_and_spoke | Adds `secondary_location`, ACR geo-replication, Flux extension. Second cluster + Front Door are manual. |
| `single_region_regulated` | ⚠️ tech preview | FIPS-enabled nodes, stricter NSGs, private state SA. Blocked by [BUG-D](KNOWN-ISSUES.md). |
| `multi_region_regulated` | ⚠️ tech preview | Combines regulated + multi-region. Blocked by [BUG-D](KNOWN-ISSUES.md). |

## Topologies

| Topology | What it does |
|---|---|
| `standalone` | No hub VNet. NAT gateway provides egress. Skips peering and firewall decisions. ✅ GA. |
| `hub_and_spoke` | The cmdlet creates a new hub VNet (with optional Azure Firewall) in the connectivity subscription, then deploys the spoke peered to it. ✅ GA single region; ⚠️ tech preview multi-region. |
| `spoke` (legacy) | Peers to an **existing** hub VNet you provide via `hub_vnet_*` fields. Useful when integrating with a prior ALZ deployment. |

---

## Cmdlet reference

```powershell
Deploy-AKSLandingZone
    -InputConfigPath <path>                            # required: path to inputs.yaml
    [-Action apply|plan|refresh|destroy|import]        # default: apply
    [-AutoApprove]                                     # skip all confirmation prompts
    [-DryRun]                                          # preview drift, change nothing
    [-Force]                                           # override hand-edit safety gate
    [-SkipPreflight]                                   # skip tool/login/RP checks
    [-StateBackup <path>]                              # for -Action import
    [-BootstrapRoot <path>]                            # override composition path
```

| Parameter | When to use it |
|---|---|
| `-Action apply` | Default. Render templates, init/plan/apply Terraform, push files to workload repo. |
| `-Action plan` | Run `terraform plan` only, stop before apply. |
| `-Action refresh` | Re-render templates and push **only the managed files** to the workload repo via `terraform apply -target=github_repository_file.this`. Skips Entra app, federated creds, state SA, RBAC bootstrap (faster than a full apply). |
| `-Action destroy` | Teardown. For hub_and_spoke, destroys the spoke first, then the hub composition. |
| `-Action import` | Push a known-good Terraform state file to the remote azurerm backend (recovery from corrupted state). Use with `-StateBackup`. |
| `-DryRun` | Preview-only. Renders templates locally, fetches each managed file from the workload repo, prints a drift report. Never runs Terraform. |
| `-Force` | Override the hand-edit safety gate. Required when a managed file in the repo has been edited directly and you want to overwrite it. |
| `-AutoApprove` | Skip both the post-wizard confirmation and the `terraform apply -auto-approve` prompt. |

---

## Re-run contract

The cmdlet manages a fixed set of files in the workload repo via
`github_repository_file.this` (one per path). Every `-Action apply` or
`-Action refresh` re-renders the templates and reconciles those files.

**Managed paths** (do **not** hand-edit these in the workload repo — they will be overwritten):

- `terraform/*.tf` (rendered from [ALZ.AKS/templates/terraform/](ALZ.AKS/templates/terraform/))
- `terraform/aks-landing-zone.auto.tfvars` (rendered from your `inputs.yaml`)
- `.github/workflows/ci.yaml`
- `.github/workflows/cd.yaml`
- `.gitignore`

Anything else in the workload repo (`README.md`, `extensions/`, your own
Kustomize overlays, `policy/`, ...) is **operator-owned** and never touched.

### Drift classification

When you run `-DryRun` or any reconcile, every managed path is classified:

| Status | Meaning | What happens on `apply` / `refresh` |
|---|---|---|
| `unchanged` | Repo content matches the freshly rendered template. | No-op. |
| `add` | File does not yet exist in the repo. | Pushed on next apply. |
| `update-managed` | A template input changed (you edited `inputs.yaml`) so the rendered content is different from what's currently in the repo. | Pushed on next apply / refresh. |
| `hand-edited` | The repo content differs from Terraform state — someone edited the file directly in GitHub. | **Blocks** apply/refresh unless `-Force` is passed. |

### Hand-edit safety gate

Without `-Force`, any `hand-edited` drift causes `-Action apply` and `-Action refresh` to abort with an ERROR listing the affected files. To proceed, either:

1. **Preserve the edit** — move it into the corresponding template under `ALZ.AKS/templates/terraform/` and re-run without `-Force`.
2. **Discard the edit** — re-run with `-Force` to overwrite the operator changes.

### Worked example

```powershell
# Preview drift
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -DryRun

# Output e.g.:
#   [unchanged] terraform/main.aks.tf       render=12345B repo=12345B state=12345B
#   [update-managed] terraform/aks-landing-zone.auto.tfvars  render=7897B repo=7665B state=7665B
#   [hand-edited] .gitignore                render=71B    repo=0B     state=71B
#   Totals: unchanged=11, update-managed=1, hand-edited=1

# Refresh blocks (because of the hand-edited .gitignore)
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -Action refresh
# [ERROR] 1 managed file(s) have been hand-edited: .gitignore
# Re-run with -Force to overwrite, or move the change into ALZ.AKS/templates/.

# Override and push
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -Action refresh -Force -AutoApprove
```

---

## Multi-environment

Each environment lives in **its own bootstrap state** and **its own workload repo** (`<service>-<env>-aks-landing-zone`). Nothing is shared across environments.

```powershell
# Create dev
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -AutoApprove

# Create test
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.test01.yaml -AutoApprove

# Create prod
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.prod01.yaml -AutoApprove
```

**Naming tip:** keep `environment_name` ≤ 8 lowercase alphanumeric characters (Azure resource name limits — Key Vault is 24 chars, Grafana is 23, and the cmdlet reserves several characters for the service + region postfix). Tags use the full env value for clarity.

Per-env state isolation comes from Terraform workspaces inside `bootstrap/alz/github/`. Each environment ends up with its own:

| Resource | Naming |
|---|---|
| State RG | `rg-<service>-<env>-state-<region>-<postfix>` |
| Identity RG | `rg-<service>-<env>-identity-<region>-<postfix>` |
| Hub RG (hub_and_spoke only) | `rg-<service>-<env>-hub-<region>-<postfix>` |
| Workload repo | `<service>-<env>-aks-landing-zone` |
| GitHub team | `<service>-<env>-approvers` |

---

## Feature flags

Toggle the platform add-ons in `inputs.yaml`:

```yaml
enable_defender_for_containers: true
enable_workload_identity:       true
enable_prometheus:              true
enable_grafana:                 true
enable_app_gateway:             false
enable_keda:                    true
enable_istio:                   false
enable_flux:                    true
enable_dapr:                    false
enable_backup:                  false
enable_cost_analysis:           true
enable_fips:                    false
enable_acr_georeplication:      false   # only with multi_region_* scenarios
```

After flipping a flag, re-run with the same `InputConfigPath` and the workload repo's `cd.yaml` workflow will reconcile the change.

---

## State recovery

If a Terraform state blob gets corrupted (rare but recoverable):

```powershell
# Inspect what's in the state backup
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -Action import -StateBackup .\path\to\good-state.tfstate
```

The cmdlet auto-discovers `errored.tfstate` in the working directory if present. After import succeeds, run `-Action apply` to reconcile.

---

## Troubleshooting

### Apply / refresh aborts with hand-edited drift
Expected behaviour. See [Re-run contract → Hand-edit safety gate](#hand-edit-safety-gate). Either move the edit into the template or pass `-Force`.

### GitHub `Name must be unique for this org` (team creation)
A previous run left an orphaned `<service>-<env>-approvers` team. Clean up:

```powershell
gh api -X DELETE orgs/<org>/teams/<service>-<env>-approvers
```

Then re-run the cmdlet.

### GitHub `Repository creation failed: name already exists`
Same as above but for the repo:

```powershell
gh api -X DELETE repos/<org>/<service>-<env>-aks-landing-zone
```

### Terraform `Error asking for state migration action: input is disabled`
You re-ran the cmdlet while a previous run left a partial local state and a partial remote backend. Either:

1. Run `-Action destroy` to roll back the partial deploy.
2. Or manually `cd bootstrap/alz/github` and delete the local `terraform.tfstate` (only if you're sure nothing was migrated to remote yet).

### `apply` workflow stuck on "Waiting for review"
Your GitHub org plan determines whether the `apply` environment can require reviewers. On Free plan with private repos, required reviewers are silently skipped. Add yourself (or anyone in `apply_approvers`) and click **Review deployments → Approve**.

### Azure Firewall Basic SKU not supported
Use `hub_firewall_sku_tier: Standard` or `Premium`. Basic SKU is intentionally not supported — it lacks the routing features the spoke UDR relies on.

### `terraform init -migrate-state` fails with 403 on regulated scenarios
This is [BUG-D](KNOWN-ISSUES.md) — the state SA in regulated topologies is private-only, so the operator workstation can't reach the data plane. Workaround: temporarily add your public IP to the SA firewall, run init, then revoke. Tracked for v1.4.1.

### Self-hosted runners — ACI container never starts
Check `TF_VAR_github_runners_personal_access_token` is set and has `admin:org` Full. The runner registration runs in the ACI container — `az container logs -g <state-rg> -n <runner-name>` shows the registration output.

---

## Resource layout reference

```
aksapplz/
├── ALZ.AKS/                          # PowerShell module
│   ├── ALZ.AKS.psd1                  # Manifest (ModuleVersion)
│   ├── ALZ.AKS.psm1                  # Cmdlet implementation
│   ├── templates/                    # Embedded into workload repo on render
│   │   ├── terraform/                # .tf templates with ${variable} substitution
│   │   ├── workflows/                # ci.yaml + cd.yaml templates
│   │   └── scenarios/                # *.tfvars per scenario
│   └── docs/                         # Engineering docs (architecture diagrams, day-2)
├── bootstrap/alz/                    # Generated bootstrap Terraform
│   ├── github/                       # Workload bootstrap composition
│   └── hub/                          # Hub composition (hub_and_spoke only)
├── config/                           # Per-environment input files
│   ├── inputs.s1-stdaln.yaml         # Standalone single region (GA)
│   ├── inputs.s2-hub.yaml            # Hub-and-spoke single region (GA)
│   └── inputs.s2.5-mrstd.yaml        # Multi-region standalone (GA)
├── QUICKSTART.md                     # End-user 5-min guide
├── ADVANCED.md                       # This file
├── KNOWN-ISSUES.md                   # Bugs + limitations
└── CHANGELOG.md                      # Release notes
```

---

## Further reading

- [KNOWN-ISSUES.md](KNOWN-ISSUES.md) — bugs fixed in GA + tech-preview limitations
- [CHANGELOG.md](CHANGELOG.md) — release notes
- [ALZ.AKS/docs/architecture-diagrams.md](ALZ.AKS/docs/architecture-diagrams.md) — per-topology diagrams
- [ALZ.AKS/docs/day2-runbook.md](ALZ.AKS/docs/day2-runbook.md) — operations runbook
- [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) — exhaustive option reference
