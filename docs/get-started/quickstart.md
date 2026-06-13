# Quickstart

> Deploy an AKS landing zone in under an hour, using one command. Make sure you've finished the
> **[Prerequisites](prerequisites.md)** first.

## 1. Install & run the latest release

```powershell
# Downloads the latest release, imports the module, makes the command available
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1)))
```

To pin a specific version instead, pass `-Release`:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod https://raw.githubusercontent.com/abengtss-max/aksapplz/main/install.ps1))) -Release v1.4.0
```

See **[Releases & versions](../releases.md)** for the full version story.

## 2. Run the wizard

```powershell
Deploy-AKSLandingZone
```

That's it. The wizard walks you through everything and asks, in order:

| # | Prompt | Example |
|---|---|---|
| 1 | Scenario | `single_region_baseline` |
| 2 | Bootstrap region | `swedencentral` |
| 3 | Bootstrap subscription | *(numbered list of your subs)* |
| 4 | **Topology** | `standalone` / `hub_and_spoke` / `spoke` |
| 5 | *(hub_and_spoke)* Hub address space, firewall SKU | `10.0.0.0/16`, `Standard` |
| 5 | *(spoke)* Existing hub VNet resource ID | *(numbered list)* |
| 6 | AKS landing-zone subscription | *(numbered list)* |
| 7 | `service_name` | `aksapplz` (3–10 lowercase chars) |
| 8 | `environment_name` | `dev01` (≤8 lowercase alphanumeric) |
| 9 | GitHub org, approvers, AKS admin Entra group | `my-org`, `[me]`, `<group-objectid>` |

!!! tip "Not sure which topology?"
    Pick **`standalone`** for your first run — no hub, NAT gateway egress, fastest path.

## 3. What happens when you confirm

1. **~10–15 min** — bootstrap runs locally: Terraform state storage, managed identities,
   federated credentials, and a new GitHub workload repo are created.
2. The command prints the URL of your new workload repo.
3. Open the repo on GitHub → **Actions** → approve the `apply` environment.
4. **~25–40 min** — AKS provisions. Done.

The wizard also saves `config/inputs.<env>.yaml` and `config/aks-landing-zone.<env>.tfvars`
so every future run is non-interactive.

## 4. Day-2 operations

```powershell
# Re-run after editing config/inputs.<env>.yaml (idempotent)
Deploy-AKSLandingZone -Environment dev01 -AutoApprove

# Preview what would change (no writes, no terraform)
Deploy-AKSLandingZone -Environment dev01 -DryRun

# Tear everything down
Deploy-AKSLandingZone -Environment dev01 -Action destroy -AutoApprove
```

## Skip the wizard (CI mode)

For pipelines or repeat deploys, pre-fill `config/inputs.<env>.yaml` and pass it directly:

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.<env>.yaml -AutoApprove
```

## If something goes wrong

| Symptom | Fix |
|---|---|
| `Get-Module ALZ.AKS` returns nothing | Re-run the install one-liner in step 1 |
| Wizard warns `TF_VAR_github_personal_access_token is not set` | Harmless — paste the PAT when prompted |
| `terraform: command not found` | Restart your shell after install |
| Command hits the wrong subscription | `az account set --subscription <id>` |
| `apply` workflow stuck waiting for review | Add your username to `apply_approvers` in `inputs.yaml` |
| `403 AuthorizationFailure` on state storage | You picked a regulated scenario (tech preview) — see [Known issues](../known-issues.md) |

Deeper diagnostics: **[Advanced](../advanced.md)**.

---

Next: **[Choose a scenario](scenarios.md)**.
