# Quick Start

> Deploy an AKS landing zone on Azure in under an hour, using one command.

---

## 1. Pick your topology

The cmdlet supports three networking topologies. **The wizard will ask you which one — this is just so you know what to pick.**

```text
┌─────────────────────────────────────────────────────────────────────────┐
│  standalone        No hub. NAT gateway egress.                          │
│                    → Dev/test, PoCs, isolated subscriptions.            │
│                    → Fastest path (~40 min total).                      │
│                                                                          │
│  hub_and_spoke     Accelerator creates a NEW hub VNet + Azure Firewall, │
│                    plus the spoke peered to it.                         │
│                    → Greenfield enterprise. (~50 min total.)            │
│                                                                          │
│  spoke             Peer to an EXISTING hub VNet you already have.       │
│                    → Brownfield: you already own an ALZ hub.            │
│                    → Available but not in v1.4.0 validation matrix.     │
└─────────────────────────────────────────────────────────────────────────┘
```

Not sure? Pick **`standalone`** for your first run.

---

## 2. Before you begin (~15 min, one-time)

### Install five tools

```powershell
winget install Microsoft.PowerShell Microsoft.AzureCLI HashiCorp.Terraform Git.Git GitHub.cli
```

Minimum versions: PowerShell 7.0, Azure CLI 2.60, Terraform 1.9.

### Sign in to Azure (as Owner)

```powershell
az login
az account set --subscription <your-subscription-id>
```

The cmdlet creates resource groups, managed identities, and role assignments — **Owner** on the target subscription is required.

### Create two fine-grained GitHub PATs

You need a GitHub **organization** account — personal accounts aren't supported (the accelerator requires features only available to orgs). Create a free org [here](https://github.com/organizations/plan) if you don't have one.

> ⚠️ On a **Free** GitHub org plan, the accelerator must create **public** repositories. Use a paid plan (Team / Enterprise) for production.

Create the PATs at <https://github.com/settings/personal-access-tokens/new> (**not** the classic tokens page).

#### Token 1 — Landing-zone PAT (always required)

| Field | Value |
|---|---|
| **Token name** | `aks-landing-zone` |
| **Resource owner** | *(select your organization from the dropdown)* |
| **Expiration** | Custom → a date that fits your policy (tomorrow is fine for a one-off bootstrap) |
| **Repository access** | **All repositories** |

**Repository permissions** — set each of these to **Read and write**:

- Actions
- Administration
- Contents
- Environments
- Secrets
- Variables
- Workflows

**Organization permissions** — set to **Read and write**:

- Members
- Self-hosted runners *(only if you'll use org-level runner groups)*

Click **Generate token** and copy the value. **Keep it handy — the wizard will prompt you for it.**

> 💡 If you'd rather not paste it interactively (e.g. CI), export it first and the wizard will pick it up:
> ```powershell
> $env:TF_VAR_github_personal_access_token = 'github_pat_...'
> ```

#### Token 2 — Runners PAT (only for self-hosted runners)

Skip this if you're using GitHub-hosted runners (default).

| Field | Value |
|---|---|
| **Token name** | `aks-landing-zone-runners` |
| **Resource owner** | *(your organization)* |
| **Expiration** | No expiration *(or set a policy and plan renewal)* |
| **Repository access** | **All repositories** *(you can narrow this post-bootstrap to just the runner repo)* |

**Repository permissions** (Read and write): `Administration`.
**Organization permissions** (Read and write): `Self-hosted runners` *(only for org-level runner groups)*.

Same deal — the wizard prompts for it. Pre-export only if you want a fully non-interactive run:

```powershell
$env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'
```

### Clone and import the module

```powershell
git clone https://github.com/abengtss-max/aksapplz.git
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
```

---

## 3. Deploy (the wizard)

### Run the cmdlet — with no arguments

```powershell
Deploy-AKSLandingZone
```

That's it. The wizard walks you through everything.

### What the wizard asks (in order)

| # | Prompt | Example |
|---|---|---|
| 1 | Scenario | `single_region_baseline` |
| 2 | Bootstrap region | `swedencentral` |
| 3 | Bootstrap subscription | (numbered list of your subs) |
| 4 | **Topology** | `standalone` / `hub_and_spoke` / `spoke` |
| 5 | (hub_and_spoke) Hub address space, firewall SKU | `10.0.0.0/16`, `Standard` |
| 5 | (spoke) Existing hub VNet resource ID | numbered list of VNets in connectivity sub |
| 6 | AKS landing-zone subscription | (numbered list) |
| 7 | `service_name` | `aksapplz` (3–10 lowercase chars) |
| 8 | `environment_name` | `dev01` (≤8 lowercase alphanumeric) |
| 9 | GitHub org, approvers, AKS admin Entra group | `my-org`, `[me]`, `<group-objectid>` |

### What happens when you confirm

1. **~10–15 min** — bootstrap runs locally: state SA, managed identities, federated creds, workload GitHub repo created.
2. The cmdlet prints the URL of your new workload repo.
3. Open the repo on GitHub → **Actions** → approve the `apply` environment.
4. **~25–40 min** — AKS provisions. Done.

> The wizard also saves `config/inputs.<env>.yaml` and `config/aks-landing-zone.<env>.tfvars` so every future run is non-interactive.

---

## 4. Day-2: re-run, preview, tear down

```powershell
# Re-run after editing config/inputs.<env>.yaml (idempotent)
Deploy-AKSLandingZone -Environment dev01 -AutoApprove

# Preview what would change (no writes, no terraform)
Deploy-AKSLandingZone -Environment dev01 -DryRun

# Tear everything down
Deploy-AKSLandingZone -Environment dev01 -Action destroy -AutoApprove
```

For details on the drift / hand-edit safety contract, see [ADVANCED.md → Re-run contract](ADVANCED.md#re-run-contract).

---

## Skip the wizard (CI mode)

For pipelines or repeat deploys, pre-fill `config/inputs.<env>.yaml` and pass it directly:

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -AutoApprove
```

YAML templates and field reference: [ADVANCED.md → inputs.yaml schema](ADVANCED.md#inputs-yaml-schema).

---

## If something goes wrong

| Symptom | Fix |
|---|---|
| `Get-Module ALZ.AKS` returns nothing | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force` |
| Wizard warns `TF_VAR_github_personal_access_token is not set` | Harmless — the wizard will prompt you. Just paste the PAT when asked. |
| `terraform: command not found` | Restart your shell after install |
| Cmdlet hits the wrong subscription | `az account set --subscription <id>` |
| `Name must be unique for this org` (GitHub team) | `gh api -X DELETE orgs/<org>/teams/<service>-<env>-approvers` |
| `apply` workflow stuck waiting for review | Add your username to `apply_approvers` in `inputs.yaml` |
| `403 AuthorizationFailure` on state SA | You picked a regulated scenario (tech preview) — see [KNOWN-ISSUES.md](KNOWN-ISSUES.md) |

Deeper diagnostics: [ADVANCED.md → Troubleshooting](ADVANCED.md#troubleshooting).

---

## Where to next

- 🔁 **Add a second environment** → [ADVANCED.md → Multi-environment](ADVANCED.md#multi-environment)
- ⚙️ **Toggle a feature flag** (Defender, Prometheus, Istio…) → [ADVANCED.md → Feature flags](ADVANCED.md#feature-flags)
- 🩹 **Recover from a bad terraform state** → [ADVANCED.md → State recovery](ADVANCED.md#state-recovery)
