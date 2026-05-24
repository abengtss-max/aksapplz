# Quick Start — Deploy an AKS Landing Zone

**Goal:** deploy a production-ready AKS cluster on Azure in under an hour.

This guide covers the two **GA-supported** paths:
- **Standalone** — fastest, no Azure hub required (good for dev/test, PoCs, isolated subscriptions).
- **Hub-and-spoke** — the accelerator creates a hub VNet + Azure Firewall, then the AKS spoke peered to it (good for production / enterprise).

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

Set them as environment variables (never commit them):

```powershell
$env:TF_VAR_github_personal_access_token         = 'github_pat_...'
$env:TF_VAR_github_runners_personal_access_token = 'github_pat_...'  # optional
```

### 4. Clone and import the module

```powershell
git clone https://github.com/abengtss-max/aksapplz.git
cd aksapplz
Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force
```

Verify:

```powershell
(Get-Module ALZ.AKS).Version   # should print 1.4.0
```

---

## Path A — Standalone (single region, ~40 min)

Best when you do **not** have an existing Azure hub VNet and want the simplest deploy.

1. Open [config/inputs.s1-stdaln.yaml](config/inputs.s1-stdaln.yaml) (or copy it to `config/inputs.my-env.yaml`) and edit the values you need to change:

   ```yaml
   service_name: aksapplz            # 3–10 lowercase chars (used in resource names)
   environment_name: dev01           # ≤8 lowercase alphanumeric chars
   bootstrap_location: swedencentral # any Azure region
   aks_landing_zone_subscription_id: <your-sub-id>
   bootstrap_subscription_id: <your-sub-id>
   github_organization_name: <your-gh-org>
   apply_approvers: ['your-gh-username']
   aks_admin_group_object_ids: ['<entra-group-objectid>']  # Entra group that gets AKS cluster-admin
   ```

2. Run the deploy:

   ```powershell
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.s1-stdaln.yaml -AutoApprove
   ```

3. What happens (~10–15 min for bootstrap):
   - Creates 2 Azure resource groups (state + identity).
   - Creates a GitHub repo `<service_name>-<env>-aks-landing-zone` with all the AKS Terraform code wired to OIDC.
   - Triggers the workload repo's GitHub Actions workflow.

4. Open the workload repo URL printed at the end. The `cd.yaml` workflow runs `plan` → waits for approval → `apply`. Approve the `apply` environment and AKS provisions in ~25–40 min.

5. **To tear it all down:**

   ```powershell
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.s1-stdaln.yaml -Action destroy -AutoApprove
   ```

---

## Path B — Hub-and-spoke (single region, ~50 min)

Best when you want enterprise-grade networking: a hub VNet with Azure Firewall, with the AKS spoke peered to it. The accelerator creates **both** the hub and the spoke for you.

1. Copy [config/inputs.s2-hub.yaml](config/inputs.s2-hub.yaml) to `config/inputs.my-env.yaml` and edit:

   ```yaml
   service_name: aksapplz
   environment_name: hub01           # ≤8 lowercase alphanumeric chars
   topology: hub_and_spoke           # ← key difference vs standalone
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

2. Deploy:

   ```powershell
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -AutoApprove
   ```

3. What happens:
   - **First**, the cmdlet creates the **hub composition** (~5 min): hub VNet, Azure Firewall, public IP, route table.
   - **Then**, the workload (spoke) composition runs: spoke VNet, peering to hub, UDR routing egress through the firewall, identity + state RGs, workload GitHub repo.
   - Approve the `apply` environment in GitHub to deploy the AKS cluster (~25–40 min).

4. **To tear it all down (spoke first, then hub):**

   ```powershell
   Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -Action destroy -AutoApprove
   ```

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

The cmdlet is idempotent. Re-run the same command to pick up config changes (e.g. flipping a feature flag in `inputs.yaml`):

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -AutoApprove
```

If you want to preview what would change **without** touching anything:

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.my-env.yaml -DryRun
```

For details on the drift / hand-edit safety contract, see [ADVANCED.md → Re-run contract](ADVANCED.md#re-run-contract).

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Get-Module ALZ.AKS` returns nothing | Module not imported | `Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force` |
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
