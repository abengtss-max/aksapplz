# AKS Application Landing Zone Accelerator

[![PSScriptAnalyzer](https://img.shields.io/badge/PSScriptAnalyzer-0%20errors-brightgreen)](.github/workflows/static-analysis.yml)
[![L1 render](https://img.shields.io/badge/L1%20render-112%20pass-brightgreen)](ALZ.AKS/tests/e2e/Scenarios.L1.Tests.ps1)
[![L2 plan](https://img.shields.io/badge/L2%20plan-60%20pass%20%2F%2012%20scenarios-brightgreen)](ALZ.AKS/tests/e2e/Scenarios.L2.Tests.ps1)
[![version](https://img.shields.io/badge/version-1.4.0--rc1-blue)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

A Terraform-based accelerator that deploys a production-ready **AKS Application Landing Zone** into an existing Azure Landing Zone, following the [Azure Landing Zones Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator) pattern.

The accelerator ships as a PowerShell module (`ALZ.AKS`) that exposes a single cmdlet — **`Deploy-AKSLandingZone`** — which renders a Terraform composition (`bootstrap/alz/github/`) and applies it. The bootstrap creates:

- Azure: managed identities + federated credentials, tfstate storage, VNet/NAT/private DNS, ACR, optional self-hosted ACI runner.
- GitHub: a workload repo (`<service_name>-<env>-aks-landing-zone`) with the AKS Terraform code, OIDC, environments, secrets/variables, and CI/CD workflows.

Then GitHub Actions deploys the AKS landing zone.

> **Status:** `1.4.0-rc4` — release candidate. Render + plan paths are fully tested across 12 scenarios; apply path verified for `01-standalone-baseline`. Destroy and state-recovery (`-Action import`) verified end-to-end on Azure 2026-05-23. Not yet on PSGallery — install from the cloned repo. See [KNOWN-ISSUES.md](KNOWN-ISSUES.md) for preview-grade limitations.

## Maturity matrix

| Capability | Status | Evidence |
|---|---|---|
| Render (template + tfvars generation) | ✅ verified | [L1 tests](ALZ.AKS/tests/e2e/Scenarios.L1.Tests.ps1) — 112 pass across 12 scenarios |
| `terraform validate` + `plan` | ✅ verified | [L2 tests](ALZ.AKS/tests/e2e/Scenarios.L2.Tests.ps1) — 60 pass across 12 scenarios |
| `terraform apply` + `destroy` | 🟡 1/12 cloud-verified | [L3 tests](ALZ.AKS/tests/e2e/Scenarios.L3.Tests.ps1) — `01-standalone-baseline` apply (11 min) + destroy (10 min) both pass on Azure. Surfaced and fixed an invalid-CIDR bug ([CHANGELOG](CHANGELOG.md)); remaining 11 scenarios scheduled before GA |
| Wizard end-to-end (`Deploy-AKSLandingZone`) | 🟡 manually verified | `standalone` + `hub_and_spoke` topologies cloud-tested 2026-05-23; automated [L4 tests](ALZ.AKS/tests/e2e/Scenarios.L4.Tests.ps1) scheduled before GA |
| Destroy (`Deploy-AKSLandingZone -Action destroy`) | ✅ shipped in v1.4.0-rc3 | [Day-2 runbook §5](ALZ.AKS/docs/day2-runbook.md#5-destroy) — automated spoke-then-hub teardown with `-AutoApprove` support |
| State recovery (`Deploy-AKSLandingZone -Action import`) | ✅ shipped in v1.4.0-rc4 | Pushes a known-good terraform state file to the remote azurerm backend. Auto-discovers `errored.tfstate` or accepts explicit `-StateBackup <path>`. Verified e2e against a corrupted-blob scenario on Azure |
| PSGallery publication | ❌ planned v1.4 | Install via `Import-Module .\ALZ.AKS\ALZ.AKS.psd1` |
| Static analysis (PSSA / tfsec / checkov) | ✅ wired | [.github/workflows/static-analysis.yml](.github/workflows/static-analysis.yml) — 0 PSSA errors |
| LICENSE / SECURITY / CHANGELOG | ✅ shipped | [LICENSE](LICENSE), [SECURITY.md](SECURITY.md), [CHANGELOG.md](CHANGELOG.md) |
| Per-topology architecture diagrams | ✅ shipped | [architecture-diagrams.md](ALZ.AKS/docs/architecture-diagrams.md) |
| Day-2 operations runbook | ✅ shipped | [day2-runbook.md](ALZ.AKS/docs/day2-runbook.md) |

---

## Deployment in 4 phases

```
┌─────────┐  ┌──────────┐  ┌──────────────┐  ┌─────────────────┐
│ Phase 0 │→ │ Phase 1  │→ │ Phase 2      │→ │ Phase 3         │
│ Plan    │  │ Pre-reqs │  │ Bootstrap    │  │ Run             │
│         │  │          │  │              │  │                 │
│ Make    │  │ Tools,   │  │ Run wizard,  │  │ GitHub Actions  │
│ all     │  │ perms,   │  │ confirm, then│  │ provisions AKS  │
│ decisions│ │ PATs,    │  │ cmdlet runs  │  │ landing zone    │
│ in the  │  │ hub VNet │  │ Terraform    │  │ from workload   │
│ checklist│ │ info     │  │              │  │ repo            │
└─────────┘  └──────────┘  └──────────────┘  └─────────────────┘
   You          You           Cmdlet            CI/CD
```

| Phase | Owner | Time | Output |
|---|---|---|---|
| **0 — Plan** | You + architects | 30–60 min | Filled-in planning checklist (every decision agreed on paper) |
| **1 — Pre-reqs** | You | 15 min | Tools installed, `az login` done, 2 PATs in env vars |
| **2 — Bootstrap** | `Deploy-AKSLandingZone` (interactive wizard, recommended) | 10–15 min | Azure bootstrap RGs + workload GitHub repo |
| **3 — Run** | GitHub Actions | 25–40 min | AKS cluster + supporting resources |

---

## Phase 0 — Plan

**Make every decision on paper before you touch the keyboard.** Do not edit `inputs.yaml` in this phase — that happens in Phase 2 once the decisions are signed off.

### 0.1 Use the planning artifacts

| Artifact | Use it for |
|---|---|
| [config/checklist.xlsx](config/checklist.xlsx) | **Primary.** One row per decision — fill with architects, networking, security, and platform teams in a single meeting. |
| [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) | Markdown checklist version — use for PR reviews / async sign-off. |
| [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) | Full reference for every option and scenario default. |

### 0.2 Pick a scenario

| Scenario | Use when | Differences from baseline |
|---|---|---|
| `single_region_baseline` | Dev / test, prod with single-region tolerance | — |
| `single_region_regulated` | Single region, regulated workloads | FIPS, Defender, stricter NSGs |
| `multi_region_baseline` | Active/active across two regions | Adds `secondary_location` + ACR geo-replication |
| `multi_region_regulated` | Multi-region, regulated workloads | Combines both |

### 0.3 Pick a network topology

| Topology | Use when | What it does |
|---|---|---|
| `spoke` *(default)* | You have an ALZ hub already | Peers the AKS spoke VNet to your existing hub, routes egress through the hub firewall via UDR |
| `standalone` | Isolated subscription, sandbox, PoC, or workloads with sub-level isolation | No hub, no peering, NAT gateway egress only. Skips Decisions 3 & 4. |
| `hub_and_spoke` *(v1.3+)* | Greenfield — you do **not** have a hub yet | Bootstrap creates a new hub VNet (+ optional Azure Firewall, Standard or Premium SKU) in the connectivity subscription, then deploys the spoke peered to it. |

### 0.4 Decisions to record in the checklist

| # | Decision | Who decides |
|---|---|---|
| 1 | Bootstrap Azure region | Platform |
| 2 | AKS landing-zone subscription ID | Platform |
| 2.5 | **Topology** — `spoke` (peer to an existing hub), `standalone` (no hub), or `hub_and_spoke` (create a new hub then peer) | Networking / Security |
| 3 | Connectivity subscription ID (hub) *(used by `spoke` and `hub_and_spoke`)* | Platform / Networking |
| 4 | Hub VNet resource ID, name, RG, firewall private IP *(only when topology = `spoke`; for `hub_and_spoke` the cmdlet captures these after the hub apply)* | Networking |
| 5 | Spoke VNet + 6 subnet CIDRs (no overlap with hub/other spokes) | Networking |
| 6 | Kubernetes version, SKU tier, private cluster yes/no, Entra cluster-admin group object ID | Platform / Security |
| 7 | Bootstrap subscription ID (usually = decision 2) | Platform |
| 8 | `service_name`, `environment_name`, `postfix_number` (resources are named `{service}-{env}-{postfix}`) | Platform |
| 9 | Self-hosted runners yes/no, private networking yes/no | Platform / Security |
| 10 | GitHub organization name, list of `apply_approvers` (GitHub usernames) | Platform / DevOps |
| 11 | Feature flags (Defender, Workload Identity, Prometheus, Grafana, App Gateway, KEDA, Istio, Flux, Dapr, Backup, Cost Analysis, FIPS, ACR geo-replication, …) | Security / Platform |

**Exit criteria for Phase 0:** every row in the checklist has an answer, signed off by the responsible team. Now proceed to Phase 1.

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

### 2.1 Interactive mode (recommended)

You do **not** need to edit `inputs.yaml` yourself — the cmdlet generates it for you from the answers you give in the wizard, using the decisions you already captured in Phase 0.

```powershell
# Clone + import
git clone <repo-url> aksapplz
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force

# Sanity-check
Get-Command Deploy-AKSLandingZone
az account show
$env:TF_VAR_github_personal_access_token         # must be set (Phase 1.4)

# Run the wizard, then bootstrap (single command)
Deploy-AKSLandingZone
```

What happens:

1. The wizard prompts you for each decision (scenario → subscriptions → networking → AKS → naming → GitHub → feature flags), pre-populating defaults from the scenario you pick.
2. It writes `config/inputs.yaml` (and a companion `config/aks-landing-zone.tfvars`).
3. It asks **"ready to run the bootstrap now?"** — answer `y` to continue, `n` to stop and review the files.
4. On `y`, the cmdlet proceeds straight to render + Terraform `init` + `plan` + `apply`.

Add `-AutoApprove` to skip both the post-wizard confirmation and the `terraform apply` confirmation. Add `-PlanOnly` to stop after `terraform plan`.

### 2.2 Advanced mode (non-interactive)

For CI/CD pipelines or when you want to manage `inputs.yaml` in source control, pre-fill the file and pass it explicitly:

1. Open [config/inputs.yaml](config/inputs.yaml) and fill each field from the Phase 0 checklist. Fields map 1:1 to the decisions you captured:

   | Decision (Phase 0) | Field(s) in `inputs.yaml` |
   |---|---|
   | 1 | `bootstrap_location` |
   | 2 | `aks_landing_zone_subscription_id` |
   | 2.5 | `topology` (`spoke`, `standalone`, or `hub_and_spoke`) |
   | 3 | `connectivity_subscription_id` *(used by `spoke` and `hub_and_spoke`)* |
   | 4 | `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip` *(only when `topology: spoke`; for `hub_and_spoke` populated automatically after the hub apply)* |
   | 4b | `hub_vnet_address_space`, `hub_deploy_firewall`, `hub_firewall_sku_tier` (`Standard` or `Premium`), `hub_firewall_subnet_address_prefix` *(only when `topology: hub_and_spoke`)* |
   | 5 | `spoke_vnet_address_space`, `subnet_address_prefix_*` (6 subnets) |
   | 6 | `kubernetes_version`, `aks_sku_tier`, `aks_private_cluster`, `aks_admin_group_object_ids` |
   | 7 | `bootstrap_subscription_id` |
   | 8 | `service_name`, `environment_name`, `postfix_number` |
   | 9 | `use_self_hosted_runners`, `use_private_networking` |
   | 10 | `github_organization_name`, `apply_approvers` |
   | 11 | `enable_*` feature flags + `scenario` |

   Do not put PATs in this file — they live only in env vars (Phase 1.4).

2. Run the cmdlet with the path:

   ```powershell
   # Dry-run
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -PlanOnly

   # Apply
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove
   ```

### 2.3 What the cmdlet does

1. **Wizard** *(interactive mode only)* — prompts for each decision, writes `config/inputs.yaml`.
2. **Preflight** — verifies tools, `az login`, registers `Microsoft.ContainerInstance` (idempotent), checks PATs.
3. **Render** — converts `inputs.yaml` → `bootstrap/alz/github/terraform.tfvars.json` and embeds the workload Terraform + workflow templates as a `repository_files` map.
4. **Terraform init + plan + apply** against `bootstrap/alz/github/`.

### 2.4 Parameters

| Parameter | Required | Description |
|---|---|---|
| `-InputConfigPath` | no | Path to a pre-filled `inputs.yaml`. **Omit to run the interactive wizard.** |
| `-PlanOnly` | no | Run `init` + `plan`, stop before `apply` |
| `-AutoApprove` | no | Skip both the post-wizard "ready to bootstrap?" prompt and the `terraform apply` confirmation |
| `-SkipPreflight` | no | Skip tool / login / RP checks (advanced) |
| `-BootstrapRoot` | no | Override the composition path (default `<repo>/bootstrap/alz/github`) |

### 2.5 What gets created

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

### Multi-environment strategy (dev / test / qa / prod)

Each environment lives in **its own bootstrap state and its own workload repo** (`<service>-<env>-aks-landing-zone`). State isolation comes from Terraform workspaces; nothing is shared across environments.

**Bootstrap a new environment:**

```powershell
# Wizard → writes config/inputs.<env>.yaml + config/aks-landing-zone.<env>.tfvars
Deploy-AKSLandingZone -Environment dev
Deploy-AKSLandingZone -Environment test
Deploy-AKSLandingZone -Environment prod
```

After a successful bootstrap, the cmdlet prompts **"Deploy another environment now?"** — type the next env name (`dev`, `test`, `qa`, `prod`, …) to chain runs without leaving the shell. Press Enter to finish.

**Re-run an existing environment (idempotent):**

```powershell
Deploy-AKSLandingZone -Environment prod -AutoApprove   # uses config/inputs.prod.yaml automatically
```

**Naming tip:** if `<env>` is longer than 6 characters (e.g. `production`, `sandbox1`), set `environment_short` in the per-env `aks-landing-zone.<env>.tfvars` to a 1-6 char alias (`prod`, `sbx1`) so resource names stay within Azure limits (Key Vault 24, Grafana 23). Tags continue to use the full `environment` value for clarity.

| File | Scope | Purpose |
|---|---|---|
| `config/inputs.<env>.yaml` | Bootstrap wizard | Decisions captured per env |
| `config/aks-landing-zone.<env>.tfvars` | Workload | Renders into the workload repo on bootstrap |
| Bootstrap RGs `rg-<service>-bootstrap-<env>-<region>` | Azure | One per env, isolated state container |
| Workload repo `<service>-<env>-aks-landing-zone` | GitHub | One per env, separate CI/CD lanes |

---

## Destroy

Run in reverse order:

```powershell
# 1. Destroy the AKS landing zone (Azure resources) via the workload repo's CD pipeline.
#    This MUST happen first — step 2 deletes the destroy workflow itself.
gh workflow run destroy.yaml -R <org>/<workload-repo> -f environment=<env>

# 2. Destroy the bootstrap (GitHub repo + GHA identities + bootstrap storage account)
#    and, for hub_and_spoke topology, the hub composition. The order is handled
#    automatically: spoke-bootstrap first, then hub.
Deploy-AKSLandingZone -Environment <env> -Action destroy
# or non-interactively:
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action destroy -AutoApprove
```

See [Day-2 runbook §5](ALZ.AKS/docs/day2-runbook.md#5-destroy) for the
caveats around ordering and the AKS workload teardown.

## State recovery

If the remote terraform state for the bootstrap composition gets corrupted,
deleted, or diverges from reality, push a known-good state file back to the
azurerm backend without leaving the cmdlet:

```powershell
# Auto-discover: looks for an errored.tfstate left behind by a failed apply/destroy
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action import -AutoApprove

# Explicit: push a specific state backup
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -Action import `
    -StateBackup .\backup.tfstate -AutoApprove
```

The import path always re-discovers the state RG/storage account, re-grants
`Storage Blob Data Contributor` to the operator, validates the source JSON,
creates the per-env workspace if missing, pushes the state, and post-verifies
with `terraform state list`. After a successful recovery, run
`Deploy-AKSLandingZone -Action plan` (or `apply`) to confirm the state
matches Azure.

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
