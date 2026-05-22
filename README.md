# AKS Application Landing Zone Accelerator

A Terraform-based accelerator that deploys a production-ready **AKS Application Landing Zone** into an existing Azure Landing Zone, following the [Azure Landing Zones Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator) pattern.

The accelerator ships as a PowerShell module (`ALZ.AKS`) that exposes a single cmdlet — **`Deploy-AKSLandingZone`** — which renders a Terraform composition (`bootstrap/alz/github/`) and applies it. The bootstrap creates:

- Azure: managed identities + federated credentials, tfstate storage, VNet/NAT/private DNS, ACR, optional self-hosted ACI runner.
- GitHub: a workload repo (`<service_name>-<env>-aks-landing-zone`) with the AKS Terraform code, OIDC, environments, secrets/variables, and CI/CD workflows.

Then GitHub Actions deploys the AKS landing zone.

> **Status:** Not yet on PSGallery — install from the cloned repo.

---

## Deployment in 4 phases

```
┌─────────┐  ┌──────────┐  ┌──────────────┐  ┌─────────────────┐
│ Phase 0 │→ │ Phase 1  │→ │ Phase 2      │→ │ Phase 3         │
│ Plan    │  │ Pre-reqs │  │ Bootstrap    │  │ Run             │
│         │  │          │  │              │  │                 │
│ Pick    │  │ Tools,   │  │ Deploy-AKS-  │  │ GitHub Actions  │
│ scenario│  │ perms,   │  │ LandingZone  │  │ provisions AKS  │
│ + fill  │  │ PATs,    │  │ runs         │  │ landing zone    │
│ inputs  │  │ hub VNet │  │ Terraform    │  │ from workload   │
│ .yaml   │  │ info     │  │              │  │ repo            │
└─────────┘  └──────────┘  └──────────────┘  └─────────────────┘
   You          You           Cmdlet            CI/CD
```

| Phase | Owner | Time | Output |
|---|---|---|---|
| **0 — Plan** | You | 30 min | A complete `config/inputs.yaml` |
| **1 — Pre-reqs** | You | 15 min | Tools installed, `az login` done, 2 PATs in env vars |
| **2 — Bootstrap** | `Deploy-AKSLandingZone` | 10–15 min | Azure bootstrap RGs + workload GitHub repo |
| **3 — Run** | GitHub Actions | 25–40 min | AKS cluster + supporting resources |

---

## Phase 0 — Plan

Open [config/inputs.yaml](config/inputs.yaml) and fill it in. The 11 decisions below map 1:1 to the file.

### 0.1 Pick a scenario

| Scenario | Use when | Differences from baseline |
|---|---|---|
| `single_region_baseline` | Dev / test, prod with single-region tolerance | — |
| `single_region_regulated` | Single region, regulated workloads | FIPS, Defender, stricter NSGs |
| `multi_region_baseline` | Active/active across two regions | Adds `secondary_location` + ACR geo-replication |
| `multi_region_regulated` | Multi-region, regulated workloads | Combines both |

Full option matrix: [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md).

### 0.2 Fill the 11 decisions

| # | Field(s) in `inputs.yaml` | What to provide |
|---|---|---|
| 1 | `bootstrap_location` | Azure region for bootstrap RGs (e.g. `swedencentral`) |
| 2 | `aks_landing_zone_subscription_id` | Sub where AKS will be deployed |
| 3 | `connectivity_subscription_id` | Sub holding the ALZ hub VNet + firewall |
| 4 | `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip` | From your existing ALZ hub |
| 5 | `spoke_vnet_address_space` + 6 subnet prefixes | Must not overlap with hub or other spokes |
| 6 | `kubernetes_version`, `aks_sku_tier`, `aks_private_cluster`, `aks_admin_group_object_ids` | Entra group object ID for K8s cluster-admin RBAC |
| 7 | `bootstrap_subscription_id` | Where tfstate + identities live (usually = landing-zone sub) |
| 8 | `service_name`, `environment_name`, `postfix_number` | Resources are named `{service}-{env}-{postfix}` |
| 9 | `use_self_hosted_runners`, `use_private_networking` | `true` requires Token-2 + adds ACI runner |
| 10 | `github_organization_name`, `apply_approvers` | Org name + GitHub user(s) that approve `apply` |
| 11 | Feature flags (`enable_defender`, `enable_workload_identity`, `enable_prometheus`, …) | Scenario defaults are usually correct |

> Planning workbook (Excel): [config/checklist.xlsx](config/checklist.xlsx) — fill with architects, then transcribe to `inputs.yaml`.

---

## Phase 1 — Pre-reqs

### 1.1 Tools

| Tool | Min version | Install |
|---|---|---|
| PowerShell | 7.0 | `winget install Microsoft.PowerShell` |
| Azure CLI | 2.60 | `winget install Microsoft.AzureCLI` |
| Terraform | 1.9 | `winget install HashiCorp.Terraform` |
| Git | any | `winget install Git.Git` |
| GitHub CLI | any | `winget install GitHub.cli` |

### 1.2 Azure permissions (the identity running the cmdlet)

Sign in with `az login`. The cmdlet creates a managed identity and assigns roles, so it needs to write role assignments:

| Scope | Role | Why |
|---|---|---|
| Landing-zone subscription | **Owner** | Grants the managed identity `Owner` here so Terraform can create RGs + role assignments. |
| Hub VNet resource group (connectivity sub) | **Owner** *(or Contributor + User Access Administrator)* | Grants `Network Contributor` so Terraform can create VNet peering. |
| Bootstrap subscription (usually = landing-zone sub) | **Owner** | Creates tfstate storage + grants the managed identity `Storage Blob Data Contributor`. |
| Entra tenant | *no directory role needed* | Managed identities are Azure resources, not Entra app registrations. |

### 1.3 GitHub prerequisites

- **A GitHub organization** (personal accounts are not supported).
- You are a member with permission to create repos.
- **Free org plan is supported** — branch protection and `apply`-environment required reviewers are auto-skipped on private repos (re-run after upgrading to enable them).

### 1.4 PATs (set as env vars — never committed)

| Env var | Scopes | When required |
|---|---|---|
| `TF_VAR_github_personal_access_token` | `repo`, `admin:org` (Members R/W), `workflow` | Always |
| `TF_VAR_github_runners_personal_access_token` | `admin:org` Full | Only when `use_self_hosted_runners: true` |

```powershell
$env:TF_VAR_github_personal_access_token         = 'github_pat_...'
$env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'   # optional
```

### 1.5 Azure prerequisites already in place

- ALZ hub VNet + firewall deployed in the connectivity subscription.
- Landing-zone subscription provisioned.
- Entra group(s) created for AKS cluster admins (object ID → decision 6).

Full pre-flight checklist: [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md).

---

## Phase 2 — Bootstrap

```powershell
# Clone + import
git clone <repo-url> aksapplz
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force

# Verify
Get-Command Deploy-AKSLandingZone
az account show
$env:TF_VAR_github_personal_access_token         # must be set

# 1. Dry-run
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -PlanOnly

# 2. Apply
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove
```

### What the cmdlet does

1. **Preflight** — verifies tools, `az login`, registers `Microsoft.ContainerInstance` (idempotent), checks PATs.
2. **Render** — converts `inputs.yaml` → `bootstrap/alz/github/terraform.tfvars.json` and embeds the workload Terraform + workflow templates as a `repository_files` map.
3. **Terraform init + plan + apply** against `bootstrap/alz/github/`.

### Parameters

| Parameter | Required | Description |
|---|---|---|
| `-InputConfigPath` | yes | Path to your filled `inputs.yaml` |
| `-PlanOnly` | no | Run `init` + `plan`, stop before `apply` |
| `-AutoApprove` | no | Skip the interactive `apply` confirmation |
| `-SkipPreflight` | no | Skip tool / login / RP checks (advanced) |
| `-BootstrapRoot` | no | Override the composition path (default `<repo>/bootstrap/alz/github`) |

### What gets created

**Azure** (two resource groups, named from `service_name`/`env`/`postfix`):
- tfstate storage account + container (AAD-only)
- 2 user-assigned managed identities (plan + apply) with federated credentials to the workload repo
- Spoke VNet, NAT gateway, private DNS zones, ACR (premium, optional public access for ACR Tasks)
- Optional: ACI container group running a self-hosted GitHub runner

**GitHub** (one repo: `<service_name>-<env>-aks-landing-zone`):
- Workload Terraform (`terraform/`) + workflows (`.github/workflows/ci.yaml`, `cd.yaml`)
- `plan` and `apply` environments with OIDC-only secrets (no client secrets)
- Team + repo permissions (org plan permitting)

---

## Phase 3 — Run

After Phase 2 completes, the cmdlet prints the workload repo URL.

1. Open the workload repo in GitHub.
2. Workflows run automatically on the initial push:
   - **CI** (`ci.yaml`) — `terraform fmt` + `validate` + `plan` on every PR.
   - **CD** (`cd.yaml`) — `plan` → manual approval → `apply` on push to `main`.
3. Approve the `apply` environment when prompted (an `apply_approvers` user must click "Approve and deploy").
4. `apply` provisions the AKS cluster + supporting resources (~25–40 min):
   - AKS (private, system + user node pools, separate subnets, UDR to hub firewall)
   - VNet peering spoke ↔ hub
   - Key Vault, Log Analytics, Defender, Workload Identity, Azure Policy
   - Optional: App Gateway, Prometheus, Grafana, KEDA, Istio, Flux, Dapr, Backup, Cost Analysis

To make changes later: edit Terraform in the workload repo, open a PR, merge → CI/CD re-applies.

### Re-running Phase 2

`Deploy-AKSLandingZone` is idempotent. Re-run with the same `inputs.yaml` to:
- Apply config drift (e.g. add a feature flag).
- Pick up Free → Team plan upgrade (branch protection + required reviewers get created).

---

## Destroy

Run in reverse order:

```powershell
# 1. Destroy AKS landing zone (run from the workload repo's terraform/ folder)
cd <workload-repo>/terraform
terraform destroy

# 2. Destroy the bootstrap (Azure RGs + GitHub repo + identities)
cd <accelerator-repo>/bootstrap/alz/github
terraform destroy
```

---

## Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `az login` works but cmdlet says not logged in | `Connect-AzAccount` if using the Az PowerShell module; the cmdlet only checks `az account show` |
| `Microsoft.ContainerInstance` registration conflict | Pre-registered already — cmdlet handles this; if it fails, run `az provider register --namespace Microsoft.ContainerInstance` manually |
| `github_branch_protection` / `required_reviewers` missing | Free org plan — by design. Upgrade and re-run. |
| PAT push fails 403 | Token-1 needs `repo` + `admin:org`; if pushing to a user-owned repo, use a user-scoped PAT |
| Terraform error on `apply_approvers` | Each entry must be an existing GitHub user; check spelling and case |
| Spoke VNet creation fails on peering | Caller lacks `Network Contributor` on hub RG — pre-assign manually or use Owner |

---

## Project structure

```
aksapplz/
├── ALZ.AKS/                         # PowerShell module
│   ├── ALZ.AKS.psd1                 #   manifest
│   ├── ALZ.AKS.psm1                 #   Deploy-AKSLandingZone cmdlet
│   └── docs/                        #   checklist + scenarios reference
├── bootstrap/
│   └── alz/github/                  # Terraform composition the cmdlet applies
│       ├── modules/azure/           #   Azure bootstrap resources
│       └── modules/github/          #   GitHub bootstrap resources
├── templates/                       # Workload templates (embedded into the new repo)
│   ├── terraform/                   #   AKS landing zone Terraform
│   ├── workflows/                   #   CI + CD GitHub Actions
│   └── scenarios/                   #   Pre-built tfvars per scenario
└── config/
    ├── inputs.yaml                  # ← YOU EDIT THIS
    └── checklist.xlsx               #   planning workbook
```

---

## Links

- [Pre-deployment checklist](ALZ.AKS/docs/deployment-checklist.md)
- [Scenarios and options reference](ALZ.AKS/docs/scenarios-and-options.md)
- [Azure Landing Zones Terraform Accelerator (upstream)](https://github.com/Azure/alz-terraform-accelerator)
