# AKS Application Landing Zone Accelerator

An opinionated, production-ready AKS Application Landing Zone that follows the same deployment pattern as the [Azure Landing Zones Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator). The accelerator ships as a PowerShell module (`ALZ.AKS`) that runs an interactive wizard, generates configuration files, then bootstraps everything end-to-end (Azure resources, GitHub repos, OIDC auth, CI/CD, optional self-hosted ACI runner) and pushes the Terraform code that GitHub Actions will deploy.

> **Status:** This module is currently developed locally — it is **not yet published** to the PowerShell Gallery. Install from the cloned repository (see [Installation](#1-installation)).

---

## Table of Contents

1. [Installation](#1-installation)
2. [Prerequisites](#2-prerequisites)
3. [Choose a Scenario](#3-choose-a-scenario)
4. [Deployment Flow Overview](#4-deployment-flow-overview)
5. [Step-by-Step: Bootstrap](#5-step-by-step-bootstrap)
6. [Step-by-Step: Deploy via CI/CD](#6-step-by-step-deploy-via-cicd)
7. [What Gets Created](#7-what-gets-created)
8. [Configuration Reference](#8-configuration-reference)
9. [Architecture](#architecture)
10. [Troubleshooting](#troubleshooting)
11. [Destroy](#destroy)
12. [Project Structure](#project-structure)
13. [Deployment Checklist](#13-deployment-checklist)
14. [Planning Workbook (Excel)](#14-planning-workbook-excel)

---

## 1. Installation

```powershell
# Clone the repository
git clone <repo-url> aksapplz
cd aksapplz

# Import the module for the current PowerShell session
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force

# Verify the command is available
Get-Command Deploy-AKSLandingZone
```

> The `bootstrap/Deploy-AKSLandingZone.ps1` script in the repo root is an older standalone version retained for reference. **Use the `ALZ.AKS` module** — it is the canonical implementation and is kept in sync with the embedded templates.

---

## 2. Prerequisites

> Tip: print the full pre-deployment checklist (prereqs + per-decision verification + security review) from [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md) before you start. Section [13. Deployment Checklist](#13-deployment-checklist) lists what it covers.
>
> Tip: for planning meetings with architects/stakeholders, the Excel workbook at [config/checklist.xlsx](config/checklist.xlsx) lets you fill in every decision in a single sheet before running the wizard. See [Section 14](#14-planning-workbook-excel).

The module verifies all prerequisites at startup and prints a results table. Install these before running:

| Tool | Version | Used for |
|------|---------|----------|
| PowerShell | 7.0+ | Module runtime |
| Azure CLI (`az`) | 2.60+ | Azure operations (logged in via `az login`) |
| Terraform | 1.9+ | Reported by checks; actually invoked by GitHub Actions |
| Git | any | Pushing code to GitHub |
| GitHub CLI (`gh`) | any | Creating repos/teams/environments/secrets |

You also need:

- **Two Azure subscriptions** (can be the same, but typically separate):
  - Landing zone subscription (where AKS, VNet, ACR, KV will be deployed)
  - Connectivity subscription (where your existing ALZ hub VNet + firewall live)
- **Hub VNet** already deployed (typically via `Deploy-Accelerator`)
- **Entra ID admin group** for Kubernetes cluster admin RBAC
- **GitHub organization** (or user account) where the two CI/CD repos will be created

### 2.1 Azure permissions (the identity running `Deploy-AKSLandingZone`)

Sign in with `az login` as a User account (recommended) or Service Principal that holds the roles below. The bootstrap creates a managed identity for the CI/CD pipelines and assigns it roles, so the caller must be able to write role assignments.

| Scope | Required role | Why |
|-------|---------------|-----|
| Landing-zone subscription | **Owner** | The bootstrap grants the managed identity `Owner` here (Terraform later creates RGs and writes role assignments for AKS network contributor, Grafana, etc.). Assigning `Owner` needs `Microsoft.Authorization/roleAssignments/write`, which Contributor does not have. |
| Connectivity subscription → hub VNet resource group | **Owner** *(or Contributor + User Access Administrator)* | The bootstrap grants the managed identity `Network Contributor` on this RG so Terraform can create the spoke ↔ hub VNet peering. |
| Bootstrap subscription *(defaults to the landing-zone sub)* | **Owner** | Creates the tfstate storage account/container and grants the managed identity `Storage Blob Data Contributor` on the container. |
| Microsoft Entra tenant | *No directory role required* | Managed identities are Azure resources, not Entra app registrations — no Application Administrator / Cloud App Administrator role is needed. |

This is a stricter subset of the upstream [ALZ permissions doc](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/platform-subscriptions/#3---azure-authentication-and-permissions): we don't deploy to management groups, so you do **not** need root `/` access or `Owner` on a management group.

> If you can't get `Owner` on the connectivity subscription, ask the platform team to pre-assign `Network Contributor` to the managed identity once the wizard has created it. The bootstrap step prints the exact `az role assignment create` command if it can't do it itself.

### 2.2 GitHub account & organization

- **You must use a GitHub organization** — personal accounts are not supported (same constraint as upstream ALZ; they don't expose the org features we need).
- You must be a member of the org with permission to create repositories. Token-1 (below) does the actual repo creation, so an org Owner role is not strictly required as long as the PAT can write to "All repositories".
- Free organizations are supported but the bootstrap will make the repos **public** (required for free-tier Actions features). Use a paid organization for private repos in production.

### 2.3 GitHub Personal Access Tokens — fine-grained

The wizard prompts for the PAT(s) interactively (masked input). You can also pre-set them as environment variables to skip the prompts. **Use fine-grained tokens** (Settings → Developer settings → **Personal access tokens** → **Fine-grained tokens**), matching the upstream [ALZ GitHub PAT guidance](https://azure.github.io/Azure-Landing-Zones/accelerator/1_prerequisites/github/#github-personal-access-token-pat).

For **both** tokens: set `Resource owner` = your organization and `Repository access` = **All repositories**.

#### Token 1 — `TF_VAR_github_personal_access_token` *(always required)*

Used by Terraform to create the two repos, push files, configure environments, set secrets and variables.

| Category | Permission | Access |
|----------|------------|--------|
| Repository | Actions | Read and write |
| Repository | Administration | Read and write |
| Repository | Contents | Read and write |
| Repository | Environments | Read and write |
| Repository | Secrets | Read and write |
| Repository | Variables | Read and write |
| Repository | Workflows | Read and write |
| Organization | Members | Read and write |
| Organization | Self-hosted runners | Read and write *(only if using org-level runner groups)* |

#### Token 2 — `TF_VAR_github_runners_personal_access_token` *(only when `use_self_hosted_runners = true`)*

Used by the self-hosted runner containers to register themselves with GitHub.

| Category | Permission | Access |
|----------|------------|--------|
| Repository | Administration | Read and write |
| Organization | Self-hosted runners | Read and write *(only if using org-level runner groups)* |

```powershell
# Optional pre-set (skip the wizard prompts)
$env:TF_VAR_github_personal_access_token         = "github_pat_..."
$env:TF_VAR_github_runners_personal_access_token = "github_pat_..."
```

> PATs are **never written to disk** — `inputs.yaml` only stores a placeholder string. Terraform reads the live env var at bootstrap time. The deployed pipelines authenticate to Azure with OIDC, so neither PAT is needed after bootstrap (except to renew it before expiry if you keep self-hosted runners around).

---

## 3. Choose a Scenario

The very first prompt in the wizard asks you to pick a scenario. The scenario sets sensible defaults for SKU, network policy, and feature toggles. You can still override any individual feature later.

| Scenario | AKS SKU | Network Policy | FIPS | Istio | Flux | Use case |
|---|---|---|---|---|---|---|
| `single_region_baseline` *(default)* | Standard | Calico | No | No | No | Standard AKS in one region |
| `multi_region_baseline` | Standard | Calico | No | No | Yes | Two regions, GitOps, ACR geo-replication |
| `single_region_regulated` | Premium | Azure NPM | Yes | Yes | No | PCI-DSS 4.0.1, single region |
| `multi_region_regulated` | Premium | Azure NPM | Yes | Yes | Yes | PCI-DSS 4.0.1, multi-region |

See [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md) for the full matrix.

---

## 4. Deployment Flow Overview

The accelerator has **two phases**, mirroring `Deploy-Accelerator`:

```
┌──────────────────────────────────────────────────────────────────┐
│  Phase A — Interactive Wizard (no -InputConfigPath)              │
│  ───────────────────────────────────────────────────────────     │
│  1. Run prerequisites check (table output)                       │
│  2. Prompt for target folder (default: ~/aksapplz)               │
│  3. Detect existing folder → ask to overwrite                    │
│  4. Ask: configure interactively, or edit files manually?        │
│  5. If interactive:                                              │
│     a. Query Azure for subscriptions, regions, VNets, AKS vers.  │
│     b. Walk through Scenario + Decisions 1–11                    │
│     c. Generate config/inputs.yaml + config/aks-landing-zone.tfvars│
│  6. Offer to open the config folder in VS Code                   │
│  7. Ask: "Ready to bootstrap now?"                               │
│       Yes → continues automatically into Phase B                 │
│       No  → exits with the exact re-run command                  │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│  Phase B — Bootstrap Execution (with -InputConfigPath)           │
│  ───────────────────────────────────────────────────────────     │
│  Pre-flight: Register required Azure resource providers          │
│  Step 1/6:   Terraform backend (RG + ZRS storage + container)    │
│  Step 2/6:   Managed identity in dedicated RG + OIDC fed creds   │
│  Step 3/6:   GitHub: repos, team, environments, secrets, vars,   │
│              branch protection, approver gate                    │
│  Step 4/6:   ACI self-hosted runner (only if enabled):           │
│              builds runner image via ACR Tasks, deploys ACI,     │
│              optional VNet + NAT Gateway + private endpoints     │
│  Step 5/6:   Push Terraform code → `{service}-{env}` repo        │
│  Step 6/6:   Push reusable workflow templates →                  │
│              `{service}-{env}-templates` repo                    │
└──────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────┐
│  Phase C — GitOps Run (operated through PRs)                     │
│  ───────────────────────────────────────────────────────────     │
│  • Developer edits aks-landing-zone.auto.tfvars in a branch      │
│  • PR opened → CI runs `terraform plan`                          │
│  • PR merged → CD runs plan → waits for approver → applies       │
└──────────────────────────────────────────────────────────────────┘
```

All Phase B steps are **idempotent** — safe to re-run.

---

## 5. Step-by-Step: Bootstrap

### Step 5.1 — Log in to Azure

```powershell
az login
az account set --subscription "<your-aks-subscription-id>"
```

The wizard will prompt for your GitHub PAT(s) interactively (masked input) in Decision 10 — you do **not** need to set anything up-front. If you prefer to skip the prompts (useful for re-runs or CI), pre-set the env vars and the wizard will detect them and offer to keep the existing value:

```powershell
# Optional — pre-fills the PAT prompts (see Section 2.3 for the full permission list)
$env:TF_VAR_github_personal_access_token         = "github_pat_..."   # fine-grained PAT (token-1)
$env:TF_VAR_github_runners_personal_access_token = "github_pat_..."   # fine-grained PAT (token-2) — only if self-hosted runners
```

### Step 5.2 — Run the wizard

```powershell
Deploy-AKSLandingZone
```

You will be prompted in this order:

| # | Prompt | Notes |
|---|--------|-------|
| 0 | Target folder | Default `~/aksapplz`. The wizard creates `config/`, `terraform/`, `workflows/` under it. |
| 1 | Configure interactively? | `yes` walks the decisions, `no` drops blank templates and exits. |
| 2 | **Scenario** | Pick one of four (see [Section 3](#3-choose-a-scenario)). |
| 3 | Secondary region | Only for multi-region scenarios. |
| 4 | Bootstrap location | Lists every Azure region; `[AZ]` flags Availability-Zone-capable regions. |
| 5 | AKS landing zone subscription | Numbered list of your enabled subscriptions. |
| 6 | Connectivity subscription | Subscription that holds the hub VNet. |
| 7 | Hub VNet | Wizard **lists existing VNets** in the connectivity sub. Pick one and the resource ID, name, and RG are parsed automatically. |
| 8 | Hub firewall private IP | Default `10.0.0.4`. |
| 9 | Spoke VNet + 6 subnets | Defaults shown for each (see [Subnets](#82-default-subnet-layout)). |
| 10 | Kubernetes version | Wizard **queries `az aks get-versions`** for the selected region and lists latest patches. |
| 11 | AKS SKU tier | `Free` / `Standard` / `Premium` (scenario sets default). |
| 12 | Private cluster | Default `true`. |
| 13 | Entra ID admin group object IDs | Comma-separated GUIDs. |
| 14 | Bootstrap subscription | Where the TF state + managed identity live. |
| 15 | Naming | `service_name` (default `aksapplz`), `environment_name` (default `prod`), `postfix_number` (default `1`). |
| 16 | Self-hosted runners | Default `true` → triggers ACI runner deployment in Phase B. |
| 17 | Private networking | Default `true` → ACR moves to Premium with private endpoints, NAT Gateway is created. |
| 18 | **GitHub PAT** (`TF_VAR_github_personal_access_token`) | **Masked `Read-Host` prompt.** If the env var is already set, the wizard shows the masked value and asks if you want to keep it; otherwise you paste the PAT here. The wizard exports it to the env var for the bootstrap step. |
| 19 | **GitHub runners PAT** (`TF_VAR_github_runners_personal_access_token`) | Same behavior — only asked when `use_self_hosted_runners = true`. |
| 20 | GitHub org name | Required. |
| 21 | Apply approvers | Comma-separated GitHub usernames added to the approver team. |
| 22 | Feature toggles | One prompt per option in [Section 8.3](#83-feature-toggles). Press Enter to accept scenario default. |

At the end, the wizard writes:

- `~/aksapplz/config/inputs.yaml`
- `~/aksapplz/config/aks-landing-zone.tfvars`

PATs are **never written to file** — `inputs.yaml` only contains placeholder text like `"Set via environment variable TF_VAR_github_personal_access_token"`. The actual value lives only in the current PowerShell session's environment, where Terraform reads it at bootstrap time.

### Step 5.3 — Review the config files

The wizard offers to open `~/aksapplz/config/` in VS Code. Review both files.

### Step 5.4 — Run the bootstrap

If you answered "yes" to the final "Ready to bootstrap now?" prompt, the bootstrap starts immediately. Otherwise, run it explicitly:

```powershell
Deploy-AKSLandingZone -InputConfigPath ~\aksapplz\config\inputs.yaml
```

Useful flags:

- `-Force` — skip the "Proceed with bootstrap? (yes/no)" confirmation (for CI/automation).
- `-Destroy` — print the destroy procedure (see [Destroy](#destroy)).

You'll see headers for **Pre-flight + Steps 1/6 … 6/6** and a final summary box with all created resources.

---

## 6. Step-by-Step: Deploy via CI/CD

After the bootstrap finishes, the GitOps flow runs entirely on GitHub.

### Step 6.1 — Clone the generated repo

```powershell
git clone https://github.com/<your-org>/<service>-<env>.git
cd <service>-<env>
```

### Step 6.2 — Make a change

Edit `aks-landing-zone.auto.tfvars` (it was pushed pre-filled with your wizard answers). All Terraform values live in this single file.

```powershell
git checkout -b my-change
# edit aks-landing-zone.auto.tfvars
git commit -am "Describe the change"
git push origin my-change
```

### Step 6.3 — Open a Pull Request

CI (`.github/workflows/ci.yaml`) automatically runs `terraform plan` and posts results to the PR. The PR cannot be merged until CI passes (enforced by branch protection on `main`).

### Step 6.4 — Merge & approve

Merging to `main` triggers CD (`.github/workflows/cd.yaml`):

1. CD runs `terraform plan` again in the `{service}-plan` environment.
2. CD then waits in the `{service}-apply` environment — a member of the **approver team** (`{service}-{env}-approvers`) must click **Approve** in the GitHub Actions UI.
3. After approval, `terraform apply` runs.

You can also trigger the CD workflow manually via **Actions → workflow_dispatch** with action `apply` or `destroy`.

### Step 6.5 — Connect to your cluster

```powershell
az aks get-credentials `
  --resource-group "rg-<service>-<env>-*" `
  --name           "aks-<service>-<env>-*"

kubectl get nodes
```

For private clusters, connect from a VM in the spoke/hub, or use:

```powershell
az aks command invoke `
  --resource-group "rg-<service>-<env>-*" `
  --name           "aks-<service>-<env>-*" `
  --command "kubectl get nodes"
```

---

## 7. What Gets Created

### Azure (in the bootstrap subscription, location = `bootstrap_location`)

| Resource | Name pattern |
|----------|--------------|
| Resource group (backend) | `rg-{svc}-{env}-{loc}-{postfix}` |
| Storage account (TF state) | `st{svc}{env}{loc}{postfix}` — Standard_ZRS, shared key disabled, 7-day soft delete, versioning |
| Blob container | `tfstate` |
| Resource group (identity) | `rg-{svc}-{env}-{loc}-identity` |
| User-assigned managed identity | `id-{svc}-{env}-{loc}-{postfix}` |
| Federated credentials | `fc-{svc}-plan`, `fc-{svc}-apply` |

If `use_self_hosted_runners = true`, additionally:

| Resource | Name pattern |
|----------|--------------|
| Resource group (agents) | `rg-{svc}-{env}-{loc}-agents` |
| Resource group (network) | `rg-{svc}-{env}-{loc}-network` *(private networking only)* |
| Container Registry | `acr{svc}{env}{loc}` (Premium when private, Basic otherwise) |
| ACI container group | `aci-{svc}-{env}-{loc}-runner` (4 vCPU / 16 GB / always-on, GitHub runner) |
| VNet + NAT Gateway + PEs | *(private networking only)* `vnet-{svc}-{env}-{loc}-agents`, `nat-…-agents`, `pip-…-nat`, ACR + storage PEs in `snet-pe` |

### Role assignments granted to the managed identity

| Role | Scope | Why |
|------|-------|-----|
| `Owner` | AKS landing zone subscription | Terraform creates RGs **and** role assignments — `Contributor` cannot do the latter. |
| `Network Contributor` | Hub VNet's **resource group** (not whole sub) | VNet peering only; least privilege. |
| `Storage Blob Data Contributor` | `tfstate` container | Read/write Terraform state. |
| `AcrPull` (separate identity `id-…-aci`) | ACR registry | ACI pulls the runner image. *(self-hosted only)* |

### GitHub (in `github_organization_name`)

| Resource | Name |
|----------|------|
| Repo (infrastructure) | `{service}-{env}` |
| Repo (reusable workflows) | `{service}-{env}-templates` — `access_level=organization` |
| Team | `{service}-{env}-approvers` (added as admin on both repos) |
| Environment | `{service}-plan` |
| Environment | `{service}-apply` (gated — team approval required) |
| Repo secrets | `ARM_CLIENT_ID`, `ARM_TENANT_ID`, `ARM_SUBSCRIPTION_ID` |
| Repo variables | `BACKEND_RESOURCE_GROUP`, `BACKEND_STORAGE_ACCOUNT`, `BACKEND_CONTAINER`, `BACKEND_KEY` |
| Branch protection | `main` — require PR + CI green + 1 approving review, dismiss stale reviews |

---

## 8. Configuration Reference

### 8.1 Decisions

| # | Key(s) in `inputs.yaml` | Default |
|---|--------------------------|---------|
| Scenario | `scenario`, `secondary_location` | `single_region_baseline`, `""` |
| 1 | `bootstrap_location` | `swedencentral` |
| 2 | `aks_landing_zone_subscription_id` | current `az` subscription |
| 3 | `connectivity_subscription_id` | — |
| 4 | `hub_vnet_resource_id`, `hub_vnet_name`, `hub_vnet_resource_group_name`, `hub_firewall_private_ip` | autodetected / `10.0.0.4` |
| 5 | spoke + 6 subnets | see below |
| 6 | `kubernetes_version`, `aks_sku_tier`, `aks_private_cluster`, `aks_admin_group_object_ids` | latest patch / `Standard` / `true` / `[]` |
| 7 | `bootstrap_subscription_id` | same as Decision 2 |
| 8 | `service_name`, `environment_name`, `postfix_number` | `aksapplz` / `prod` / `1` |
| 9 | `use_self_hosted_runners`, `use_private_networking` | `true` / `true` |
| 10 | `github_organization_name`, `apply_approvers`, PAT env vars | — |
| 11 | feature toggles (see 8.3) | scenario-driven |

### 8.2 Default subnet layout

```
spoke_vnet_address_space = 10.10.0.0/16
├── snet-aks-system-*    10.10.0.0/24    System node pool (CriticalAddonsOnly)
├── snet-aks-user-*      10.10.16.0/22   User/workload node pool
├── snet-aks-apiserver-* 10.10.20.0/28   API Server VNet Integration
├── snet-agw-*           10.10.21.0/24   Application Gateway WAF v2
├── snet-pe-*            10.10.22.0/24   Private endpoints (ACR, Key Vault)
└── snet-ingress-*       10.10.23.0/24   Ingress LB
```

System and user node pools use **separate subnets** per AKS Baseline guidance.

### 8.3 Feature toggles

All toggles live in `aks-landing-zone.auto.tfvars` and `inputs.yaml`. Scenario defaults shown.

| Toggle | `single_region_baseline` | `multi_region_baseline` | `single_region_regulated` | `multi_region_regulated` |
|---|---|---|---|---|
| `enable_defender` | ✓ | ✓ | ✓ | ✓ |
| `enable_workload_identity` | ✓ | ✓ | ✓ | ✓ |
| `enable_azure_policy` | ✓ | ✓ | ✓ | ✓ |
| `enable_prometheus` | ✓ | ✓ | ✓ | ✓ |
| `enable_grafana` | ✓ | ✓ | ✓ | ✓ |
| `enable_app_gateway` | ✓ | ✓ | ✓ | ✓ |
| `enable_keda` | ✓ | ✓ | ✓ | ✓ |
| `enable_vpa` | – | ✓ | ✓ | ✓ |
| `enable_node_auto_provisioning` | – | ✓ | – | – |
| `enable_istio` | – | – | ✓ | ✓ |
| `enable_flux` | – | ✓ | – | ✓ |
| `enable_dapr` | – | – | – | – |
| `enable_fips` | – | – | ✓ | ✓ |
| `enable_backup` | – | ✓ | ✓ | ✓ |
| `enable_cost_analysis` | – | – | ✓ | ✓ |
| `enable_acr_geo_replication` | – | ✓ | – | ✓ |

> **Always-on (not toggleable):** Azure Container Registry, Azure Key Vault, Azure RBAC for Kubernetes, local accounts disabled, Image Cleaner, CSI drivers (blob/disk/file), snapshot controller, diagnostic settings.

Full option reference: [ALZ.AKS/docs/scenarios-and-options.md](ALZ.AKS/docs/scenarios-and-options.md).

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Hub VNet (managed by ALZ — connectivity subscription)                   │
│  ┌────────────┐   ┌──────────────────┐                                   │
│  │  Firewall   │   │ VPN/ExpressRoute │                                   │
│  └─────┬──────┘   └──────────────────┘                                   │
└────────┼─────────────────────────────────────────────────────────────────┘
         │ VNet Peering (Network Contributor on hub VNet RG)
┌────────┼─────────────────────────────────────────────────────────────────┐
│  Spoke VNet 10.10.0.0/16 (AKS landing zone subscription)                 │
│        │                                                                  │
│  ┌─────┴──────────┐  ┌────────────────┐  ┌──────────────┐                │
│  │ AKS system     │  │ AKS user nodes │  │ API server   │                │
│  │ 10.10.0.0/24   │  │ 10.10.16.0/22  │  │ 10.10.20/28  │                │
│  └────────────────┘  └────────────────┘  └──────────────┘                │
│  ┌────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │ App Gateway    │  │ Private endpoints │  │ Ingress           │         │
│  │ WAF v2         │  │ (ACR, Key Vault)  │  │                   │         │
│  │ 10.10.21.0/24  │  │ 10.10.22.0/24     │  │ 10.10.23.0/24     │         │
│  └────────────────┘  └──────────────────┘  └──────────────────┘          │
└─────────────────────────────────────────────────────────────────────────-┘
```

### Azure Verified Modules used

| AVM | Purpose |
|-----|---------|
| `Azure/avm-res-containerservice-managedcluster/azurerm` | AKS cluster |
| `Azure/avm-res-network-virtualnetwork/azurerm` | Spoke VNet |
| `Azure/avm-res-containerregistry-registry/azurerm` | Azure Container Registry |
| `Azure/avm-res-keyvault-vault/azurerm` | Key Vault |
| `Azure/avm-res-network-applicationgateway/azurerm` | Application Gateway WAF |
| `Azure/avm-res-dashboard-grafana/azurerm` | Managed Grafana |
| `Azure/avm-res-operationalinsights-workspace/azurerm` | Log Analytics |

---

## Troubleshooting

### "Resource provider not registered"
The Pre-flight step registers all required providers (ContainerService, Network, Storage, KeyVault, ContainerRegistry, OperationalInsights, insights, Monitor, ManagedIdentity, Authorization, plus Dashboard/Security/KubernetesConfiguration/DataProtection when their features are enabled). If registration is slow, Terraform retries on first apply.

### OIDC `AADSTS70021` / 401 during `terraform init`
- Federated credential subject must match exactly: `repo:<org>/<repo>:environment:<env>`.
- GitHub org and repo names are case-sensitive — match the exact casing in `github_organization_name`.

### `gh` reports "team not found" or "user not a member"
- Token-1 needs the **Organization → Members: Read and write** permission (see [Section 2.3](#23-github-personal-access-tokens--fine-grained)).
- Each `apply_approvers` username must already be a member of the GitHub organization.

### Private cluster: `kubectl` times out
- API server is in a private subnet. Connect from the spoke/hub or use `az aks command invoke`.
- If `use_self_hosted_runners = true`, CI/CD already runs inside the spoke and works.

### ACR build fails with "Forbidden"
- Happens on re-runs when ACR is already locked down. The module temporarily flips `public-network-enabled true` + `default-action Allow` for the build, then re-locks. If your environment forbids the public toggle, run `az acr build` from a peered network.

### Branch protection fails to set
- Free GitHub orgs only support protected branches on **public** repos. The module already creates public repos by default; for private, upgrade to GitHub Pro/Team.

---

## Destroy

```powershell
Deploy-AKSLandingZone -Destroy
```

This prints (but does not execute) the destroy procedure so you stay in control:

```powershell
# 1. Destroy Terraform-managed resources first
git clone https://github.com/<org>/<service>-<env>.git
cd <service>-<env>
terraform destroy -auto-approve

# 2. Then delete bootstrap resources
az group delete --name rg-<service>-<env>-<loc>-001          --yes  # TF state RG
az group delete --name rg-<service>-<env>-<loc>-identity     --yes  # identity RG
az group delete --name rg-<service>-<env>-<loc>-agents       --yes  # if self-hosted runners
az group delete --name rg-<service>-<env>-<loc>-network      --yes  # if private networking
gh repo delete <org>/<service>-<env>           --yes
gh repo delete <org>/<service>-<env>-templates --yes
```

---

## Project Structure

```
aksapplz/
├── ALZ.AKS/                         # ← Canonical PowerShell module (use this)
│   ├── ALZ.AKS.psd1
│   ├── ALZ.AKS.psm1
│   ├── docs/
│   │   ├── deployment-checklist.md
│   │   └── scenarios-and-options.md
│   ├── templates/                   # Embedded templates shipped with the module
│   │   ├── README.md                # README pushed into the generated repo
│   │   ├── config/                  # inputs.yaml + aks-landing-zone.tfvars templates
│   │   ├── scenarios/               # Pre-built tfvars per scenario
│   │   ├── terraform/               # All Terraform code pushed to {svc}-{env} repo
│   │   ├── workflows/               # ci/cd.yaml + ci/cd-template.yaml
│   │   └── docs/
│   ├── tests/                       # Pester tests
│   ├── TEST-PLAN.md
│   └── TEST-RESULTS.md
│
├── bootstrap/                       # ← Legacy standalone script (kept for reference)
│   └── Deploy-AKSLandingZone.ps1
├── terraform/                       # ← Legacy copy of templates (kept for reference)
├── workflows/                       # ← Legacy copy of templates (kept for reference)
├── config/                          # Planning workbook + legacy yaml/tfvars
│   ├── checklist.xlsx               #   ← Excel planning workbook (see Section 14)
│   ├── generate_checklist.py        #   ← openpyxl generator for checklist.xlsx
│   ├── inputs.yaml                  #   legacy
│   └── aks-landing-zone.tfvars      #   legacy
└── README.md                        # This file
```

> The duplicates under `bootstrap/`, `terraform/`, `workflows/`, and the `*.yaml`/`*.tfvars` files under `config/`, predate the PowerShell module refactor. The wizard reads exclusively from `ALZ.AKS/templates/`. They will be removed in a future revision. The Excel workbook and its generator under `config/` are kept — see [Section 14](#14-planning-workbook-excel).

---

## 13. Deployment Checklist

A printable, end-to-end checklist lives at [ALZ.AKS/docs/deployment-checklist.md](ALZ.AKS/docs/deployment-checklist.md). It covers:

- **Pre-Deployment** — prerequisites, Azure prerequisites, GitHub prerequisites
- **Scenario Selection** — matrix + sizing checks
- **Configuration Decisions** — one checklist block per Decision 1–11
- **Security** — identity & access, network security, secrets, image, runtime
- **Post-deployment validation** — cluster health, RBAC, monitoring, networking

Use it as the gate before merging your first PR in the generated `{service}-{env}` repo.

---

## 14. Planning Workbook (Excel)

For planning sessions with architects, security, and platform stakeholders, an Excel workbook is provided at [config/checklist.xlsx](config/checklist.xlsx). Fill in the yellow "Your Value" column for every decision before running the wizard — the wizard prompts map 1:1 to the workbook rows.

**Tabs:**

| Tab | Contents |
|---|---|
| `Instructions` | How to use the workbook end-to-end. Shown first. |
| `Accelerator - Bootstrap` | Decisions 0–11 — **maps 1:1 to the wizard prompts**. Scenario, landing-zone-type, subscriptions, hub/spoke networking (with the real system+user split subnets), AKS config, naming, runners, GitHub, and the full 16-toggle feature matrix. Dropdowns enforce valid values. |
| `Accelerator - AKS Landing Zone` | Advanced `.tfvars`-level settings: per-pool compute, CNI/dataplane/CIDR, AKS lifecycle (upgrade channels, AZs), App Gateway WAF, monitoring, ACR + Key Vault. These come from `ALZ.AKS/templates/scenarios/{scenario}.tfvars`. |

**Regenerate the workbook:**

```powershell
pip install openpyxl
python .\config\generate_checklist.py
# writes config/checklist.xlsx
```

> **PATs go in the wizard, not the workbook.** Rows 10a/10b in Tab 1 are documentation only — paste the PAT into the masked `Read-Host` prompt during the wizard (or pre-set the env vars).

---

## License

MIT
