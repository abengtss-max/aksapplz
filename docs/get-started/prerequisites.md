# Prerequisites

One-time setup, about 15 minutes. Do this once per workstation.

## 1. Install the tools

| Tool | Minimum version | Notes |
|---|---|---|
| PowerShell | 7.0 | required |
| Azure CLI | 2.60 | required |
| Terraform | 1.9 | required |
| Git | any recent | required |
| GitHub CLI | any recent | required |
| VS Code | any recent | recommended — the wizard offers to open the generated config in VS Code for review when `code` is on your `PATH` |

=== "Windows 10 / 11"

    `winget` ships with these editions, so one line installs everything (VS Code
    is optional but recommended):

    ```powershell
    winget install Microsoft.PowerShell Microsoft.AzureCLI HashiCorp.Terraform Git.Git GitHub.cli Microsoft.VisualStudioCode
    ```

=== "Windows Server"

    Windows Server **does not include `winget`** (you'll get
    `'winget' is not recognized`). Run this Windows-PowerShell 5.1 bootstrap **as Administrator**
    instead — it installs Chocolatey, then every tool through it:

    ```powershell
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    choco install -y powershell-core azure-cli terraform git gh vscode
    ```

    `vscode` is optional but recommended — with it installed, the wizard offers to
    open the generated config for review. Drop it from the list to skip.

    Prefer no third-party package manager? Install the official MSIs directly:

    ```powershell
    [System.Net.ServicePointManager]::SecurityProtocol = 3072
    $tmp = "$env:TEMP\alz-tools"; New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $downloads = @{
      'PowerShell-7.msi' = 'https://github.com/PowerShell/PowerShell/releases/latest/download/PowerShell-7.4.6-win-x64.msi'
      'AzureCLI.msi'     = 'https://aka.ms/installazurecliwindowsx64'
      'Git.exe'          = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe'
      'gh.msi'           = 'https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_windows_amd64.msi'
    }
    foreach ($name in $downloads.Keys) {
      Invoke-WebRequest -Uri $downloads[$name] -OutFile "$tmp\$name"
      Start-Process -Wait -FilePath "$tmp\$name" -ArgumentList '/quiet /norestart'
    }
    ```

    Terraform has no installer — unzip the binary and add it to `PATH`:

    ```powershell
    Invoke-WebRequest 'https://releases.hashicorp.com/terraform/1.9.8/terraform_1.9.8_windows_amd64.zip' -OutFile "$tmp\terraform.zip"
    Expand-Archive "$tmp\terraform.zip" -DestinationPath 'C:\terraform' -Force
    [Environment]::SetEnvironmentVariable('Path', $env:Path + ';C:\terraform', 'Machine')
    ```

!!! tip
    Restart your shell (or sign out and back in) after installing so the new tools are on your `PATH`.
    On Windows Server, launch **PowerShell 7** (`pwsh`) for the rest of this guide — not the
    Windows PowerShell 5.1 console you used to bootstrap.

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
