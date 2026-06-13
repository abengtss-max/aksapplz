# Prerequisites

One-time setup, about 15 minutes. Do this once per workstation.

## 1. Install the tools

```powershell
winget install Microsoft.PowerShell Microsoft.AzureCLI HashiCorp.Terraform Git.Git GitHub.cli
```

| Tool | Minimum version |
|---|---|
| PowerShell | 7.0 |
| Azure CLI | 2.60 |
| Terraform | 1.9 |
| Git | any recent |
| GitHub CLI | any recent |

!!! tip
    Restart your shell after installing so the new tools are on your `PATH`.

## 2. Sign in to Azure (as Owner)

```powershell
az login
az account set --subscription <your-subscription-id>
```

The accelerator creates resource groups, managed identities, and role assignments, so you need
**Owner** on the target subscription.

## 3. Create a GitHub organization

You need a GitHub **organization** account — personal accounts aren't supported. Create a free
org [here](https://github.com/organizations/plan) if you don't have one.

!!! warning "Free org plans create public repos"
    On a **Free** GitHub org plan the accelerator must create **public** repositories. Use a paid
    plan (Team / Enterprise) for production workloads.

## 4. Create a fine-grained GitHub PAT

Create the token at
[github.com/settings/personal-access-tokens/new](https://github.com/settings/personal-access-tokens/new)
(**not** the classic tokens page).

| Field | Value |
|---|---|
| **Token name** | `aks-landing-zone` |
| **Resource owner** | *your organization* |
| **Expiration** | a date that fits your policy |
| **Repository access** | All repositories |

**Repository permissions** — set each to **Read and write**: Actions, Administration, Contents,
Environments, Secrets, Variables, Workflows.

**Organization permissions** — **Read and write**: Members (and Self-hosted runners only if you
use org-level runner groups).

Generate and copy the token. The wizard prompts you for it — or pre-export it for a non-interactive run:

```powershell
$env:TF_VAR_github_personal_access_token = 'github_pat_...'
```

??? note "Self-hosted runners (optional)"
    If you opt into self-hosted runners, create a **second** PAT named `aks-landing-zone-runners`
    with **Administration: Read and write** (repo) and **Self-hosted runners: Read and write** (org),
    then export it:

    ```powershell
    $env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'
    ```

---

Next: **[Planning checklist](planning-checklist.md)** — agree on your settings before you deploy, then **[Quickstart](quickstart.md)**.
