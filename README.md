# AKS Application Landing Zone Accelerator

[![version](https://img.shields.io/badge/version-1.4.0-brightgreen)](CHANGELOG.md)
[![license](https://img.shields.io/badge/license-MIT-lightgrey)](LICENSE)

A Terraform-based accelerator that deploys a production-ready **AKS Application Landing Zone** on Azure. It ships as a PowerShell module (`ALZ.AKS`) with a single cmdlet — `Deploy-AKSLandingZone` — that bootstraps the infrastructure, creates a workload GitHub repository, and wires up CI/CD via OIDC.

```
You → Deploy-AKSLandingZone → Azure (state + identity)
                            → GitHub workload repo
                            → GitHub Actions deploys AKS
```

---

## Get started

| If you want to... | Read |
|---|---|
| **Deploy AKS in under an hour** | [QUICKSTART.md](QUICKSTART.md) |
| Configure scenarios, drift, multi-env, troubleshooting | [ADVANCED.md](ADVANCED.md) |
| See what's fixed in this release and what's tech preview | [KNOWN-ISSUES.md](KNOWN-ISSUES.md) |
| Read release notes | [CHANGELOG.md](CHANGELOG.md) |

---

## GA-supported scenarios (v1.4.0)

| Scenario | Topology | Region mode | Use case |
|---|---|---|---|
| `single_region_baseline` | `standalone` | single | Dev/test, PoCs, isolated subscriptions |
| `single_region_baseline` | `hub_and_spoke` | single | Enterprise — accelerator creates hub + Azure Firewall + spoke |
| `multi_region_baseline` | `standalone` | multi | Dev/test geo-redundancy |

Tech preview (planned for v1.4.1): regulated topologies and multi-region hub-and-spoke. See [KNOWN-ISSUES.md](KNOWN-ISSUES.md).

---

## What it provisions

**Azure** (per environment):
- 2 user-assigned managed identities (plan + apply) with OIDC federated credentials to GitHub
- Terraform state storage account + container (AAD-only auth)
- AKS cluster, Spoke VNet, NAT gateway, private DNS zones, ACR, Key Vault, Log Analytics, Defender, Workload Identity
- Hub VNet + Azure Firewall (only when `topology: hub_and_spoke`)

**GitHub** (one repo per environment):
- All AKS Terraform under `terraform/`
- `ci.yaml` (fmt + validate + plan on PRs) and `cd.yaml` (plan → approval → apply on `main`)
- `plan` and `apply` environments with OIDC-only secrets

---

## Project structure

```
aksapplz/
├── ALZ.AKS/                # PowerShell module
├── bootstrap/alz/          # Generated bootstrap Terraform
├── config/                 # Per-environment inputs.yaml files
├── QUICKSTART.md           # ← Start here
├── ADVANCED.md             # Full reference
├── KNOWN-ISSUES.md
└── CHANGELOG.md
```

---

## Project status

- **License:** [MIT](LICENSE)
- **Security:** [SECURITY.md](SECURITY.md)
- **Code of Conduct:** [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
