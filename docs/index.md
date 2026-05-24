---
hide:
  - navigation
  - toc
---

# AKS Application Landing Zone Accelerator

<p style="font-size: 1.15em; max-width: 700px;">
A Terraform-based accelerator that deploys a production-ready
<strong>AKS Application Landing Zone</strong> on Azure. Ships as a single PowerShell
cmdlet — <code>Deploy-AKSLandingZone</code> — that bootstraps Azure, creates a workload
GitHub repository, and wires up OIDC-based CI/CD.
</p>

[Get started in 30 minutes :material-arrow-right:](QUICKSTART.md){ .md-button .md-button--primary }
[View on GitHub :material-github:](https://github.com/abengtss-max/aksapplz){ .md-button }

---

## Pick your path

<div class="grid cards" markdown>

-   :material-cube-outline:{ .lg .middle } &nbsp; **Standalone**

    ---

    Fastest path. No Azure hub VNet required. Best for **dev / test**,
    PoCs, or isolated subscriptions.

    NAT-gateway egress, ~40 min end-to-end.

    [:octicons-arrow-right-24: Deploy standalone](QUICKSTART.md#path-a-standalone-single-region-40-min)

-   :material-hub:{ .lg .middle } &nbsp; **Hub-and-spoke**

    ---

    Enterprise-grade networking. The accelerator creates the **hub VNet +
    Azure Firewall + spoke** for you in a single command.

    Firewall-routed egress, ~50 min end-to-end.

    [:octicons-arrow-right-24: Deploy hub-and-spoke](QUICKSTART.md#path-b-hub-and-spoke-single-region-50-min)

-   :material-book-open-variant:{ .lg .middle } &nbsp; **Advanced reference**

    ---

    Scenarios, cmdlet parameters, the re-run contract, drift handling,
    multi-environment patterns, and troubleshooting.

    [:octicons-arrow-right-24: Read the full reference](ADVANCED.md)

</div>

---

## What it provisions

=== "Azure (per environment)"

    - 2 user-assigned managed identities (plan + apply) with OIDC federated credentials to GitHub
    - Terraform state storage account + container (AAD-only auth)
    - AKS cluster, Spoke VNet, NAT gateway, private DNS zones, ACR (premium SKU)
    - Key Vault, Log Analytics, Defender for Containers, Workload Identity, Azure Policy
    - Hub VNet + Azure Firewall (only when `topology: hub_and_spoke`)

=== "GitHub (per environment)"

    - One workload repository: `<service_name>-<env>-aks-landing-zone`
    - All AKS Terraform under `terraform/`
    - `ci.yaml` — fmt + validate + plan on PRs
    - `cd.yaml` — plan → approval → apply on `main`
    - `plan` and `apply` environments with OIDC-only secrets (no client secrets)

---

## GA-supported scenarios (v1.4.0)

| Scenario | Topology | Region mode | Use case |
|---|---|---|---|
| `single_region_baseline` | `standalone` | single | Dev/test, PoCs, isolated subscriptions |
| `single_region_baseline` | `hub_and_spoke` | single | Enterprise — accelerator creates hub + Azure Firewall + spoke |
| `multi_region_baseline` | `standalone` | multi | Dev/test geo-redundancy |

!!! info "Tech preview"
    Regulated topologies and multi-region hub-and-spoke are tech preview in v1.4.0
    and planned for GA in v1.4.1. See [Known issues](KNOWN-ISSUES.md).

---

## Status

- **Current release:** [v1.4.0](CHANGELOG.md) — General Availability
- **License:** [MIT](https://github.com/abengtss-max/aksapplz/blob/main/LICENSE)
- **Security:** [SECURITY.md](https://github.com/abengtss-max/aksapplz/blob/main/SECURITY.md)
