# AKS Application Landing Zone Accelerator

An opinionated, production-ready AKS Application Landing Zone that follows the same deployment pattern as the [Azure Landing Zones Terraform Accelerator](https://github.com/Azure/alz-terraform-accelerator). Uses Azure Verified Modules (AVM) throughout for standardized, Microsoft-supported infrastructure-as-code.

**No repository cloning needed.** Install the PowerShell module and run `Deploy-AKSLandingZone` — the module ships with all Terraform, workflow, and configuration templates embedded, just like `Deploy-Accelerator`.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Hub VNet (managed by ALZ)                                              │
│  ┌────────────┐   ┌──────────────────┐                                  │
│  │  Firewall   │   │  VPN/ExpressRoute│                                  │
│  └─────┬──────┘   └──────────────────┘                                  │
│        │                                                                 │
└────────┼─────────────────────────────────────────────────────────────────┘
         │ VNet Peering
┌────────┼─────────────────────────────────────────────────────────────────┐
│  Spoke VNet (10.10.0.0/16)                                              │
│        │                                                                 │
│  ┌─────┴──────┐   ┌──────────────┐   ┌──────────────────┐              │
│  │ AKS Nodes  │   │ API Server   │   │ App Gateway WAF  │              │
│  │ 10.10.0/20 │   │ 10.10.16/28  │   │ 10.10.17.0/24    │              │
│  └────────────┘   └──────────────┘   └──────────────────┘              │
│                                                                         │
│  ┌──────────────────┐   ┌──────────────────┐                            │
│  │ Private Endpoints │   │ Ingress           │                           │
│  │ 10.10.18.0/24     │   │ 10.10.19.0/24     │                           │
│  └──────────────────┘   └──────────────────┘                            │
└─────────────────────────────────────────────────────────────────────────┘
```

## Features

| Feature | Description |
|---------|-------------|
| **AKS Best Practices** | System + user node pools, CriticalAddonsOnly taint, ephemeral OS disks, auto-upgrade |
| **Entra ID Integration** | Azure RBAC for Kubernetes with admin group binding |
| **Workload Identity** | OIDC issuer + workload identity enabled for pod-level Azure access |
| **Defender for Containers** | Microsoft Defender security monitoring enabled |
| **Managed Prometheus** | Azure Monitor workspace with data collection rules |
| **Managed Grafana** | Azure Managed Grafana integrated with Prometheus data |
| **KEDA** | Event-driven autoscaling for workloads |
| **Application Gateway WAF v2** | OWASP 3.2 + Bot Manager rules, autoscale 1-10 |
| **Private Cluster** | API server VNet integration for private access |
| **Azure CNI Overlay** | Scalable networking without IP exhaustion |
| **ACR with Private Endpoint** | Premium container registry with zone redundancy |
| **Key Vault with Private Endpoint** | RBAC-enabled secret management with purge protection |
| **UDR to Hub Firewall** | All egress routed through centralized firewall |
| **Azure Policy** | Policy addon enabled for governance |

## Prerequisites

- **Azure CLI** v2.60+ (logged in with `az login`)
- **PowerShell** 7+
- **Terraform** v1.9+
- **GitHub CLI** (`gh`) installed
- **Azure Subscriptions**: Landing zone subscription + connectivity subscription (hub)
- **Entra ID Group**: Admin group for AKS cluster admin access
- **Hub VNet**: Existing hub VNet with firewall (deployed by ALZ)

The module checks all prerequisites automatically and displays them in a table format, identical to `Deploy-Accelerator`.

## Installation

```powershell
# Install or update the ALZ.AKS module
$module = Get-InstalledPSResource -Name ALZ.AKS 2>$null
if (-not $module) {
    Install-PSResource -Name ALZ.AKS
} else {
    Update-PSResource -Name ALZ.AKS
}
```

> **Local development:** If you've cloned this repository, import the module directly:
> ```powershell
> Import-Module .\ALZ.AKS\ALZ.AKS.psd1
> ```

## Deployment Process

The deployment follows the same two-phase execution pattern as the ALZ Terraform Accelerator `Deploy-Accelerator`:

```
Phase 0: Planning
  └─► Fill in the checklist (config/checklist.xlsx)

Phase 1: Prerequisites
  └─► Azure CLI login, GitHub PATs via env vars, Entra ID group

Phase 2a: Bootstrap — Interactive (no -InputConfigPath)
  ├─► Checks software requirements (formatted table)
  ├─► Prompts for target folder (default: ~/aksapplz)
  ├─► Detects existing folder, asks overwrite yes/no
  ├─► Asks "configure interactively?" — skip to edit files manually
  ├─► Queries Azure for subscriptions and regions
  ├─► Prompts for each decision with numbered selection lists
  ├─► Generates config/inputs.yaml and config/aks-landing-zone.tfvars
  ├─► Warns about sensitive values stored as env vars
  ├─► Asks "open config folder in VS Code?"
  └─► STOPS — user reviews and edits config files before executing

Phase 2b: Bootstrap — Execution (with -InputConfigPath)
  ├─► Step 1: Create Terraform state storage
  ├─► Step 2: Create managed identity + OIDC federation
  ├─► Step 3: Bootstrap GitHub (repos, teams, environments, secrets)
  ├─► Step 4: Push Terraform code → {service_name}-{environment_name} repo
  └─► Step 5: Push workflow templates → {service_name}-{environment_name}-templates repo

Phase 3: Run
  ├─► Developer creates PR → CI runs plan
  ├─► Reviewer approves PR → merge to main
  └─► CD runs plan → approval gate → apply
```

## Quick Start

### 1. Set Environment Variables (PATs)

Set your GitHub Personal Access Tokens as environment variables (same pattern as `Deploy-Accelerator`):

```powershell
$env:TF_VAR_github_personal_access_token = "ghp_..."
$env:TF_VAR_github_runners_personal_access_token = "ghp_..."  # Only if use_self_hosted_runners = true
```

Required PAT scopes:
| PAT | Scopes |
|-----|--------|
| `github_personal_access_token` | `repo`, `admin:org` (Members: Read and Write), `workflow` |
| `github_runners_personal_access_token` | `admin:org` (Full control) |

### 2. Run Interactive Mode (Phase 2a)

Start from an empty filesystem — just like `Deploy-Accelerator`. No cloning, no local files needed:

```powershell
Deploy-AKSLandingZone
```

The wizard will:
1. Check all software requirements and display a formatted table
2. Prompt for a target folder (default: `~/aksapplz`)
3. Create the folder structure (config, terraform, workflows)
4. Ask if you want to configure interactively or edit files manually
5. If interactive: query Azure for regions and subscriptions, then prompt for each decision with numbered selection lists showing `[AZ]` badges and `(current)` markers
6. Generate `config/inputs.yaml` and `config/aks-landing-zone.tfvars` with your chosen values
7. Warn about sensitive values stored via environment variables
8. Offer to open the config folder in VS Code for review
9. **STOP** — the bootstrap does NOT execute yet

### 3. Review and Edit Config Files

Open VS Code (prompted automatically) and review/edit:
- `config/inputs.yaml` — bootstrap decisions
- `config/aks-landing-zone.tfvars` — AKS landing zone configuration

| Decision | Parameter | Description | Default |
|----------|-----------|-------------|----------|
| 1 | `bootstrap_location` | Azure region for bootstrap resources | `swedencentral` |
| 2 | `aks_landing_zone_subscription_id` | AKS target subscription | (current CLI sub) |
| 3 | `connectivity_subscription_id` | Hub/connectivity subscription | — |
| 4 | `hub_vnet_resource_id` / `hub_firewall_private_ip` | Hub VNet and firewall IP | — |
| 5 | `spoke_vnet_address_space` + subnets | Spoke networking CIDRs | `10.10.0.0/16` |
| 6 | `kubernetes_version` / `aks_sku_tier` / `aks_private_cluster` | AKS settings | `1.31` / `Standard` / `true` |
| 7 | `bootstrap_subscription_id` | Bootstrap resources subscription | (same as Decision 2) |
| 8 | `service_name` / `environment_name` / `postfix_number` | Naming convention | `aksapplz` / `prod` / `1` |
| 9 | `use_self_hosted_runners` / `use_private_networking` | CI/CD agent options | `true` / `true` |
| 10 | `github_organization_name` / `apply_approvers` | GitHub settings | — |
| 11 | `enable_defender` / `enable_keda` / `enable_prometheus` / ... | Feature toggles | all `true` |

### 4. Execute Bootstrap (Phase 2b)

Once you've reviewed the config files, run the command again with `-InputConfigPath`:

```powershell
Deploy-AKSLandingZone -InputConfigPath ~\aksapplz\config\inputs.yaml
```

The bootstrap creates:
- Terraform state storage (resource group + storage account + container)
- Managed identity with OIDC federated credentials for GitHub Actions
- Two GitHub repositories (`{service_name}-{environment_name}` and `{service_name}-{environment_name}-templates`)
- GitHub team, environments (plan + apply with approval gate), secrets, and branch protection
- Pushes all Terraform code and CI/CD workflows to the repositories

All bootstrap steps are **idempotent** — safe to re-run if a step fails.

### 5. Deploy via CI/CD (Phase 3 - Run)

1. Create a branch in the main repository
2. Edit `aks-landing-zone.auto.tfvars` and commit changes
3. Create a Pull Request → CI automatically runs `terraform plan`
4. Review the plan output
5. Merge the PR → CD triggers:
   - Plan step runs in `{service_name}-plan` environment
   - Apply step waits for approval in `{service_name}-apply` environment
   - Approver from the team reviews and approves → Terraform applies

### Destroy

```powershell
Deploy-AKSLandingZone -Destroy
```

## Project Structure

### Module Structure (what you install)

```
ALZ.AKS/                                    # PowerShell module (publishable to PSGallery)
├── ALZ.AKS.psd1                             # Module manifest
├── ALZ.AKS.psm1                             # Module script (Deploy-AKSLandingZone function)
└── templates/                               # Embedded templates (shipped with module)
    ├── terraform/                           # All Terraform files
    │   ├── terraform.tf                     # Provider and backend configuration
    │   ├── locals.tf                        # Naming conventions and computed values
    │   ├── main.networking.tf               # Spoke VNet, subnets, NSGs, UDR, peering
    │   ├── main.aks.tf                      # AKS cluster (AVM module)
    │   ├── main.security.tf                 # ACR + Key Vault with private endpoints
    │   ├── main.appgateway.tf               # Application Gateway WAF v2
    │   ├── main.monitoring.tf               # Log Analytics, Prometheus, Grafana
    │   ├── variables.tf                     # Input variables with defaults
    │   └── outputs.tf                       # Resource outputs
    ├── workflows/                           # CI/CD workflow templates
    │   ├── ci.yaml                          # CI caller workflow (PRs)
    │   ├── cd.yaml                          # CD caller workflow (main branch)
    │   ├── ci-template.yaml                 # Reusable CI template
    │   └── cd-template.yaml                 # Reusable CD template
    └── config/                              # Configuration templates
        ├── inputs.yaml                      # Bootstrap configuration template
        └── aks-landing-zone.tfvars          # Terraform variable values template
```

### Generated Output (what the wizard creates in ~/aksapplz)

```
~/aksapplz/                                  # Target folder (user-specified)
├── terraform/                               # Terraform files (copied from module)
├── workflows/                               # Workflow files (copied from module)
└── config/
    ├── inputs.yaml                          # Generated with your interactive choices
    └── aks-landing-zone.tfvars              # Generated with your values
```

## Azure Verified Modules Used

| Module | Purpose |
|--------|---------|
| [avm-res-containerservice-managedcluster](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm) | AKS cluster |
| [avm-res-network-virtualnetwork](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm) | Spoke VNet |
| [avm-res-containerregistry-registry](https://registry.terraform.io/modules/Azure/avm-res-containerregistry-registry/azurerm) | Container Registry |
| [avm-res-keyvault-vault](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm) | Key Vault |
| [avm-res-network-applicationgateway](https://registry.terraform.io/modules/Azure/avm-res-network-applicationgateway/azurerm) | Application Gateway WAF |
| [avm-res-dashboard-grafana](https://registry.terraform.io/modules/Azure/avm-res-dashboard-grafana/azurerm) | Managed Grafana |
| [avm-res-operationalinsights-workspace](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm) | Log Analytics |

## Networking Design

- **Spoke VNet** peered bidirectionally to the hub VNet
- **UDR** on the AKS nodes subnet routes `0.0.0.0/0` to the hub firewall
- **NSGs** on each subnet with least-privilege rules
- **Private endpoints** for ACR and Key Vault on a dedicated subnet
- **API Server VNet Integration** eliminates need for private DNS zone for API server access
- **Azure CNI Overlay** avoids IP exhaustion — pods get overlay IPs, not VNet IPs

## Customization

### Disabling Features

Toggle features in `aks-landing-zone.tfvars`:

```hcl
enable_defender     = false  # Disable Defender for Containers
enable_keda         = false  # Disable KEDA autoscaling
enable_prometheus   = false  # Disable Managed Prometheus
enable_grafana      = false  # Disable Managed Grafana
enable_app_gateway  = false  # Disable Application Gateway WAF
```

### Changing Network Ranges

Update the subnet CIDR blocks in `aks-landing-zone.tfvars`:

```hcl
spoke_vnet_address_space = ["10.20.0.0/16"]
subnet_address_prefixes = {
  aks_nodes       = "10.20.0.0/20"
  aks_api_server  = "10.20.16.0/28"
  app_gateway     = "10.20.17.0/24"
  ...
}
```

### Adding Node Pools

Add additional user node pools by extending the AKS module configuration in `main.aks.tf`.

## Security Considerations

- All secrets managed through Key Vault with RBAC
- Private endpoints for all PaaS services (ACR, Key Vault)
- Network policies enforced via Azure CNI
- WAF with OWASP 3.2 rule set at the ingress
- Defender for Containers for runtime threat detection
- Workload Identity for pod-level Azure authentication (no stored credentials)
- AKS auto-upgrade channel set to `patch` for security patches
- Image Cleaner enabled to remove unused container images

## Troubleshooting

### OIDC Authentication Failures

If GitHub Actions fails with 401 during `terraform init`:
- Verify the federated credential subject matches exactly: `repo:<org>/<repo>:environment:<env>`
- Check case sensitivity — GitHub org/repo names must match the exact casing

### Private Cluster Access

With `private_cluster = true` and API Server VNet Integration:
- Use a self-hosted runner deployed in the spoke VNet or peered network
- Azure Bastion can be used for emergency `kubectl` access

### VNet Peering Issues

- Ensure the managed identity has `Network Contributor` on both hub and spoke VNets
- VNet address spaces must not overlap

## License

MIT
