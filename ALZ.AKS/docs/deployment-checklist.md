# AKS Application Landing Zone — Deployment Checklist

This checklist aligns with the [Azure Landing Zone Accelerator](https://aka.ms/alz/acc) review process and covers all scenarios and options.

## Pre-Deployment Checklist

### Prerequisites
- [ ] Azure CLI installed and logged in (`az login`)
- [ ] PowerShell 7+ installed
- [ ] Terraform >= 1.9 installed
- [ ] GitHub CLI (`gh`) installed
- [ ] Git installed
- [ ] GitHub PAT created with scopes: `repo`, `admin:org` (Members R/W), `workflow` *(can be pasted into the wizard or set via `$env:TF_VAR_github_personal_access_token`)*
- [ ] Runner PAT created with scope: `admin:org` Full (if using self-hosted runners) *(env var: `$env:TF_VAR_github_runners_personal_access_token`)*
- [ ] ALZ.AKS module imported from clone: `Import-Module .\ALZ.AKS\ALZ.AKS.psd1 -Force` *(module is not yet published to PSGallery)*

### Azure Prerequisites
- [ ] Azure Landing Zone deployed (hub VNet, firewall, connectivity subscription)
- [ ] AKS landing zone subscription provisioned and enabled
- [ ] Entra ID group created for AKS cluster admins
- [ ] Entra ID group created for Grafana admins
- [ ] Hub VNet resource ID identified
- [ ] Hub firewall private IP identified
- [ ] Spoke VNet address space planned (no overlap with hub)

### GitHub Prerequisites
- [ ] GitHub organization exists (or personal account)
- [ ] Organization allows repository creation
- [ ] Organization allows team creation

---

## Scenario Selection

| Scenario | SKU | Network Policy | FIPS | Istio | Flux | Premium Features |
|----------|-----|---------------|------|-------|------|-----------------|
| `single_region_baseline` | Standard | Calico | No | No | No | Baseline |
| `multi_region_baseline` | Standard | Calico | No | No | Yes | VPA, Backup, NAP |
| `single_region_regulated` | Premium | Azure NPM | Yes | Yes | No | All compliance |
| `multi_region_regulated` | Premium | Azure NPM | Yes | Yes | Yes | All + multi-region |

- [ ] Scenario selected and understood
- [ ] SKU tier appropriate for workload requirements
- [ ] Network policy appropriate for compliance requirements

---

## Configuration Decisions

### Decision 1: Bootstrap Location
- [ ] Azure region selected with Availability Zone support
- [ ] Region aligned with data residency requirements

### Decision 2: AKS Landing Zone Subscription
- [ ] Correct subscription selected for AKS workload
- [ ] Subscription has required resource provider registrations (or auto-register enabled)

### Decision 3: Connectivity Subscription
- [ ] Hub networking subscription identified
- [ ] Cross-subscription peering permissions in place

### Decision 4: Hub Networking
- [ ] Hub VNet resource ID provided
- [ ] Hub VNet resource group name provided
- [ ] Hub firewall private IP address confirmed
- [ ] Firewall rules allow AKS egress (see [AKS required outbound rules](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress))

### Decision 5: Spoke Networking
- [ ] Spoke VNet address space does not overlap with hub or other spokes
- [ ] System node pool subnet sized appropriately (/24 default = 256 IPs)
- [ ] User node pool subnet sized appropriately (/22 default = 1024 IPs)
- [ ] API server subnet is at least /28
- [ ] All subnet ranges verified non-overlapping

### Decision 6: AKS Configuration
- [ ] Kubernetes version selected (use default unless specific version required)
- [ ] SKU tier matches scenario (Standard for baseline, Premium for regulated)
- [ ] Private cluster enabled for corp landing zones
- [ ] Entra ID admin group object IDs provided
- [ ] Availability zones enabled (3 zones default)

### Decision 7: Bootstrap Subscription
- [ ] Bootstrap resources subscription selected (typically same as AKS subscription)

### Decision 8: Resource Naming
- [ ] Service name defined (used in all resource names)
- [ ] Environment name defined (dev/staging/prod)
- [ ] Postfix number defined for uniqueness

### Decision 9: Networking and Agents
- [ ] Self-hosted runner decision made
- [ ] Private networking decision made
- [ ] If private networking: NAT Gateway will be created for outbound

### Decision 10: Version Control
- [ ] GitHub PAT set as environment variable
- [ ] Runner PAT set as environment variable (if applicable)
- [ ] GitHub organization name provided
- [ ] Apply approvers list defined

### Decision 11: Features & Options
- [ ] Feature toggles reviewed against scenario defaults
- [ ] Non-default features justified (documented reason for enabling/disabling)

---

## Security Checklist

### Identity & Access
- [ ] Workload Identity enabled (pod-level Entra ID)
- [ ] Azure RBAC for Kubernetes enabled
- [ ] Local Kubernetes accounts disabled
- [ ] Entra ID admin groups configured
- [ ] Image cleaner enabled (stale image removal)

### Network Security
- [ ] Private cluster enabled (corp)
- [ ] API Server VNet Integration enabled
- [ ] NSGs applied to all subnets
- [ ] UDR routes traffic through hub firewall (corp)
- [ ] VNet peering configured with correct transit settings
- [ ] Network policy enabled (Calico or Azure NPM)

### Data Protection
- [ ] Key Vault with RBAC and purge protection
- [ ] ACR Premium with zone redundancy
- [ ] Private endpoints for ACR and Key Vault (corp)
- [ ] Terraform state in encrypted storage with soft delete

### Permissions (Least Privilege)
- [ ] Managed Identity: Contributor scoped to AKS subscription only
- [ ] Managed Identity: Network Contributor scoped to hub VNet RG only
- [ ] Managed Identity: Storage Blob Data Contributor scoped to tfstate container only
- [ ] AKS Identity: Network Contributor scoped to spoke VNet only
- [ ] AKS Identity: AcrPull scoped to ACR only
- [ ] AKS Identity: Key Vault Secrets User scoped to Key Vault only
- [ ] Grafana: Monitoring Reader scoped to resource group only
- [ ] No tenant-level permissions created
- [ ] No Owner role assignments

### Compliance (Regulated Scenarios)
- [ ] FIPS 140-2 enabled for node OS
- [ ] Azure network policy (NPM) for PCI-DSS segmentation
- [ ] Istio service mesh for mTLS
- [ ] Defender for Containers enabled
- [ ] Azure Policy add-on enabled
- [ ] Diagnostic settings enabled for audit trail
- [ ] Backup enabled for data protection

---

## Post-Deployment Checklist

### Validation
- [ ] GitHub repository created with correct structure
- [ ] CI workflow triggers on pull requests
- [ ] CD workflow triggers on push to main
- [ ] Branch protection active on main
- [ ] Environment protection active on apply environment
- [ ] Team approval gate working
- [ ] Terraform plan succeeds
- [ ] Terraform apply succeeds (after approval)

### AKS Cluster Access
- [ ] `az aks get-credentials` works
- [ ] `kubectl get nodes` shows expected node count
- [ ] System node pool has CriticalAddonsOnly taint
- [ ] User node pool accepts workload pods
- [ ] Nodes spread across availability zones

### Monitoring
- [ ] Container Insights data flowing to Log Analytics
- [ ] Prometheus metrics collecting
- [ ] Grafana dashboards accessible
- [ ] Diagnostic settings active on all resources

### Networking
- [ ] VNet peering established (corp)
- [ ] UDR forwarding to firewall verified (corp)
- [ ] Private endpoints resolving (corp)
- [ ] Ingress path validated

---

## Alignment with ALZ Accelerator

The AKS Application Landing Zone Accelerator aligns with the standard [Azure Landing Zone Accelerator](https://github.com/Azure/ALZ-PowerShell-Module) pattern:

| ALZ Accelerator Concept | AKS LZ Implementation |
|------------------------|----------------------|
| Phase 0: Prerequisites | Software check, Azure login, PAT creation |
| Phase 1: Planning | 11 decisions with interactive prompts |
| Phase 2: Bootstrap | 6-step automated bootstrap |
| Phase 3: Run | CI/CD workflows, PR-based governance |
| Scenarios | 4 scenarios (baseline/regulated × single/multi-region) |
| Options | 17 feature toggles across 6 categories |
| IaC Module Choice | Azure Verified Modules (Terraform) |
| VCS Bootstrap | GitHub repos, teams, environments, branch protection |
| Identity | Managed Identity with OIDC federated credentials |
| Self-Hosted Agents | ACI-based GitHub Actions runners (optional) |

> **Note:** The ALZ Accelerator does include scenarios/options as a formal concept. Our 4 scenarios and 17 options follow this pattern for AKS-specific deployments.
