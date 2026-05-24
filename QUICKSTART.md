# Quick Start — Deploy an AKS Landing Zone

**Goal:** deploy a production-ready AKS cluster on Azure in under an hour.

Two ways to drive the cmdlet:

- **Interactive wizard (recommended for first run)** — run the cmdlet with no arguments and it walks you through every decision, writes the config file for you, and starts the deploy.
- **Advanced / non-interactive** — pre-fill a YAML file and pass it via `-InputConfigPath` (good for CI, repeat deploys, or when you already know your values).

The two GA-supported topologies are:
- **Standalone** — fastest, no Azure hub VNet required (dev/test, PoCs, isolated subs).
- **Hub-and-spoke** — the accelerator creates a hub VNet + Azure Firewall, then the AKS spoke peered to it (enterprise / prod).

Everything else (regulated topologies, multi-region hub-and-spoke) is tech preview — see [ADVANCED.md](ADVANCED.md).

---

## Prerequisites (15 min, do once)

### 1. Install tools

| Tool | Min version | Install on Windows |
|---|---|---|
| PowerShell | 7.0 | `winget install Microsoft.PowerShell` |
| Azure CLI | 2.60 | `winget install Microsoft.AzureCLI` |
| Terraform | 1.9 | `winget install HashiCorp.Terraform` |
| Git | any | `winget install Git.Git` |
| GitHub CLI | any | `winget install GitHub.cli` |

### 2. Sign in to Azure

```powershell
az login
az account set --subscription <your-subscription-id>
```

You need **Owner** on the target subscription (the cmdlet creates resource groups, role assignments, and managed identities).

### 3. Create two GitHub PATs

You need a GitHub **organization** (personal accounts are not supported). On https://github.com/settings/personal-access-tokens/new, create:

| PAT | Scopes | Required when |
|---|---|---|
| Landing-zone PAT | `repo`, `admin:org` (Members R/W), `workflow` | Always |
| Runners PAT | `admin:org` Full | Only if you want self-hosted runners |

Export them as environment variables (the wizard warns if missing):

```powershell
$env:TF_VAR_github_personal_access_token         = 'github_pat_...'
$env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'  # optional
```

### 4. Clone and import the module

```powershell
git clone https://github.com/abengtss-max/aksapplz.git
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
(Get-Module ALZ.AKS).Version    # should print 1.4.0
```

---

## Path A — Interactive wizard (recommended)

Just run the cmdlet with **no** `-InputConfigPath`:

```powershell
Deploy-AKSLandingZone
```

The wizard walks you through, in order:

1. **Scenario** — `single_region_baseline` (GA) or `multi_region_baseline` (GA for standalone only).
2. **Bootstrap location** — any Azure region, picked from a numbered list (e.g. `swedencentral`).
3. **Bootstrap subscription** — from a numbered list of your `az account list` subs.
4. **Topology** — `standalone` or `hub_and_spoke`.
5. **(hub_and_spoke only)** Connectivity subscription, hub VNet address space, Azure Firewall deploy + SKU (Standard/Premium).
6. **AKS landing-zone subscription** — where the workload + AKS go.
7. **service_name** — 3–10 lowercase chars (used in resource names; e.g. `aksapplz`).
8. **environment_name** — ≤8 lowercase alphanumeric chars (e.g. `dev01`).
9. **GitHub organization, approvers, AKS admin Entra group object id(s).**

When the wizard finishes it:
- Writes `config/inputs.<env>.yaml` — keep this file; future re-runs read from it.
- Writes `config/aks-landing-zone.<env>.tfvars`.
- Asks for one final confirmation, then runs `terraform init` → `plan` → `apply`.

End-to-end timing:
- ~10–15 min for bootstrap (state SA, identities, federated creds, workload GitHub repo).
- ~25–40 min for AKS once you approve the workload repo's `apply` environment in GitHub Actions.

**Re-run later** — every subsequent run is non-interactive:

```powershell
Deploy-AKSLandingZone -Environment dev01 -AutoApprove
# equivalent to:
# Deploy-AKSLandingZone -InputConfigPath .\config\inputs.dev01.yaml -AutoApprove
```

**Tear it all down:**

```powershell
Deploy-AKSLandingZone -Environment dev01 -Action destroy -AutoApprove
```

---

## Path B — Non-interactive (advanced)

Skip the wizard when you already have an `inputs.yaml`. Templates are in [config/](config/) and [ALZ.AKS/templates/config/inputs.yaml](ALZ.AKS/templates/config/inputs.yaml).

### Standalone (~40 min)

Copy a template to `config/inputs.my-env.yaml` and edit:

```yaml
service_name: aksapplz            # 3–10 lowercase chars
environment_name: dev01           # ≤8 lowercase alphanumeric chars
bootstrap_location: swedencentral
topology: standalone
aks_landing_zone_subscription_id: <your-sub-id>
bootstrap_subscription_id: <your-sub-id>
github_organization_name: <your-gh-org>
apply_approvers: ['your-gh-username']
aks_admin_group_object_ids: ['<entra-group-objectid>']
```

Deploy:

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -AutoApprove
```

### Hub-and-spoke (~50 min)

```yaml
service_name: aksapplz
environment_name: hub01
topology: hub_and_spoke           # ← key difference
bootstrap_location: swedencentral
connectivity_subscription_id: <your-sub-id>  # where the hub goes
aks_landing_zone_subscription_id: <your-sub-id>
bootstrap_subscription_id: <your-sub-id>
hub_vnet_address_space: ['10.0.0.0/16']
hub_deploy_firewall: true
hub_firewall_sku_tier: Standard   # Standard or Premium (Basic not supported)
github_organization_name: <your-gh-org>
apply_approvers: ['your-gh-username']
aks_admin_group_object_ids: ['<entra-group-objectid>']
```

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -AutoApprove
```

The cmdlet creates the **hub composition first** (~5 min: hub VNet, Azure Firewall, public IP, route table), then the spoke + workload repo. Approve the `apply` environment in GitHub Actions to provision AKS (~25–40 min).

---

## What gets created

**Azure:**
- 2 user-assigned managed identities (plan + apply) with OIDC federated credentials to GitHub
- tfstate storage account + container (AAD-only auth)
- Spoke VNet, NAT gateway, private DNS zones, ACR (premium SKU)
- AKS cluster (private, system + user node pools, separate subnets, UDR to hub firewall when applicable)
- Key Vault, Log Analytics, Defender for Containers, Workload Identity, Azure Policy
- Hub VNet + Azure Firewall (only when `topology: hub_and_spoke`)

**GitHub** (one repo per environment):
- All workload Terraform under `terraform/`
- `ci.yaml` (fmt + validate + plan on PRs) and `cd.yaml` (plan → approval → apply on `main`)
- `plan` and `apply` environments with OIDC-only secrets

---

## Re-running the same environment

The cmdlet is idempotent. Re-run to pick up config changes (e.g. flipping a feature flag in `inputs.yaml`):

```powershell
Deploy-AKSLandingZone -Environment dev01 -AutoApprove
```

Preview what would change without touching anything:

```powershell
Deploy-AKSLandingZone -Environment dev01 -DryRun
```

For details on the drift / hand-edit safety contract, see [ADVANCED.md → Re-run contract](ADVANCED.md#re-run-contract).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Get-Module ALZ.AKS` returns nothing | Module not imported | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force` |
| Wizard warns `TF_VAR_github_personal_access_token is not set` | PAT env var missing | Set both PAT env vars (prereq step 3) and re-run |
| `terraform: command not found` | Terraform not on `PATH` | Reinstall or restart shell |
| `az login` succeeds but cmdlet says wrong sub | Default subscription is wrong | `az account set --subscription <id>` |
| `Name must be unique for this org` (GitHub team error) | Leftover team from a previous attempt | `gh api -X DELETE orgs/<org>/teams/<service>-<env>-approvers` |
| `apply` workflow stuck waiting for review | You aren't in `apply_approvers` | Add your username to `apply_approvers` in `inputs.yaml` and re-run |
| `403 AuthorizationFailure` on state SA during init | You picked a regulated scenario | Regulated topologies are tech preview — see [KNOWN-ISSUES.md](KNOWN-ISSUES.md) |

For deeper diagnostics see [ADVANCED.md → Troubleshooting](ADVANCED.md#troubleshooting).

---

## Next steps

- **Add a second environment** (dev/test/prod) — see [ADVANCED.md → Multi-environment](ADVANCED.md#multi-environment).
- **Change a feature flag** (Defender, Prometheus, Istio, …) — see [ADVANCED.md → Feature flags](ADVANCED.md#feature-flags).
- **Recover from a corrupted Terraform state** — see [ADVANCED.md → State recovery](ADVANCED.md#state-recovery).
