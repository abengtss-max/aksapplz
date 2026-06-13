# Advanced

Power-user topics for operators running the accelerator beyond a first deploy.

## Re-run contract (drift & hand-edits)

`Deploy-AKSLandingZone` is idempotent. Re-running after editing `config/inputs.<env>.yaml` reconciles
the workload repo and infrastructure. To stay safe:

- **Preview first** with `-DryRun` — shows what a re-run would push without touching Terraform or
  the workload repo.
- The cmdlet **blocks** apply/refresh if an operator has hand-edited a managed file in the workload
  repo directly. Override deliberately with `-Force` once you've reconciled the change back into config.

```powershell
Deploy-AKSLandingZone -Environment dev01 -DryRun
Deploy-AKSLandingZone -Environment dev01 -AutoApprove
```

## Multiple environments

Each environment has its own `config/inputs.<env>.yaml`, its own Terraform state storage, and its
own workload repo. Switch with `-Environment`:

```powershell
Deploy-AKSLandingZone -Environment dev01 -AutoApprove
Deploy-AKSLandingZone -Environment prod01 -AutoApprove
```

## Secrets without prompting

| Mode | How |
|---|---|
| **Key Vault** | `-PatFromKeyVault <vault>` pulls the GitHub PAT(s) at runtime into `TF_VAR_*` for that process only. |
| **PAT-less / OIDC** | `-OidcOnly` authenticates the Terraform `github` provider via a GitHub App (`GITHUB_APP_*`) or a pre-minted `GH_TOKEN`/`GITHUB_TOKEN`. |

```powershell
Deploy-AKSLandingZone -Environment prod01 -PatFromKeyVault kv-platform-prod -AutoApprove
```

## State recovery

If an apply/destroy leaves a broken remote state, push a known-good state file:

```powershell
Deploy-AKSLandingZone -Environment dev01 -Action import -StateBackup .\errored.tfstate
```

When `-StateBackup` is omitted, the cmdlet looks for an `errored.tfstate` left behind by a failed run.

## Self-hosted runners

Set `use_self_hosted_runners: true` to provision an ACI-based self-hosted runner during bootstrap.
The runner container is created but must be started separately. If you'd rather use GitHub-hosted
runners, leave it `false` (the default) — the generated workflows use `ubuntu-latest`.

## Tear down

```powershell
Deploy-AKSLandingZone -Environment dev01 -Action destroy -AutoApprove
```

This destroys the AKS infrastructure and the bootstrap resources (state storage, identities,
workload repo) for that environment.

---

For the full operator runbook and deeper troubleshooting, see the
[repository docs](https://github.com/abengtss-max/aksapplz/tree/main/ALZ.AKS/docs).
