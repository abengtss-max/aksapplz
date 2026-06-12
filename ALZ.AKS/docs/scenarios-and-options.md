# AKS Landing Zone Accelerator — Scenarios & Options

## Overview

The AKS Application Landing Zone accelerator uses **scenarios** and **options** to simplify deployment.

- **Scenarios** are pre-configured architecture blueprints that set sensible defaults for a given use case
- **Options** are individual feature toggles that can be customized within any scenario

This follows the same pattern as the [Azure Landing Zones Accelerator](https://aka.ms/alz/acc/scenarios).

---

## Scenarios

| Scenario | SKU | Network Policy | FIPS | Istio | Flux | VPA | Backup | Cost Analysis | ACR Geo-Repl | Description |
|----------|-----|---------------|------|-------|------|-----|--------|---------------|--------------|-------------|
| `single_region_baseline` | Standard | Calico | No | No | No | No | No | No | No | Standard AKS baseline in one region |
| `multi_region_baseline` | Standard | Calico | No | No | Yes | Yes | Yes | No | Yes | Multi-region with Front Door, Fleet Manager |
| `single_region_regulated` | Premium | Azure | Yes | Yes | No | Yes | Yes | Yes | No | PCI-DSS 4.0.1 compliant, single region |
| `multi_region_regulated` | Premium | Azure | Yes | Yes | Yes | Yes | Yes | Yes | Yes | PCI-DSS 4.0.1 compliant, multi-region |

### Single Region Baseline

The default scenario. Deploys the [AKS Baseline Reference Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks) in a single Azure region with:

- Azure CNI Overlay + Calico network policy
- Workload Identity + Azure RBAC
- Defender for Containers
- KEDA autoscaling
- Managed Prometheus + Grafana
- Application Gateway WAF v2
- ACR (Premium, zone-redundant) + Key Vault
- System and user node pools on **separate subnets**

### Multi Region Baseline

Extends the baseline for [multi-region deployments](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster):

- Everything in single-region baseline, plus:
- **Flux v2 GitOps** for consistent multi-cluster deployments
- **VPA** for right-sizing across regions
- **Azure Backup** for cross-region recovery

### Single Region Regulated (PCI-DSS 4.0.1)

Hardened for [PCI-DSS compliance](https://learn.microsoft.com/azure/aks/pci-network-segmentation):

- **Premium SKU** (required for regulated workloads)
- **Azure network policy** (required for PCI-DSS network segmentation)
- **Istio service mesh** with mTLS for cardholder data encryption in transit
- **FIPS 140-2** compliant node OS
- **Local accounts disabled** (Entra ID only)
- **Azure Backup** for data protection
- **Cost analysis** for compliance reporting
- Higher minimum node counts (3) for regulated HA

### Multi Region Regulated (PCI-DSS 4.0.1)

Combines multi-region with regulated hardening:

- Everything in single-region regulated, plus:
- **Flux v2 GitOps** for consistent regulated deployments across regions
- Cross-region data protection with Azure Backup

---

## Options

Options are feature toggles that can be customized within any scenario. Each scenario sets sensible defaults, but you can override any option.

### Identity & Security

| Option | Default | Description |
|--------|---------|-------------|
| `enable_workload_identity` | `true` | Pod-level Entra ID authentication via federated credentials |
| `enable_azure_rbac` | `true` | Azure RBAC for Kubernetes authorization |
| `disable_local_accounts` | `true` | Enforce Entra ID only (no local kubeconfig) |
| `enable_image_cleaner` | `true` | Remove stale/vulnerable images from nodes automatically |
| `enable_azure_policy` | `true` | Azure Policy add-on for governance and compliance |
| `enable_defender` | `true` | Microsoft Defender for Containers (threat detection) |

### Monitoring

| Option | Default | Description |
|--------|---------|-------------|
| `enable_managed_prometheus` | `true` | Azure Managed Prometheus metrics collection |
| `enable_managed_grafana` | `true` | Azure Managed Grafana dashboards |
| `enable_diagnostic_settings` | `true` | Send resource diagnostics to Log Analytics |

### Scaling

| Option | Default | Description |
|--------|---------|-------------|
| `enable_keda` | `true` | KEDA event-driven autoscaling for pods |
| `enable_vpa` | Scenario | Vertical Pod Autoscaler for right-sizing |
| `enable_node_auto_provisioning` | `false` | Node Auto Provisioning (NAP / Karpenter) |

### Networking

| Option | Default | Description |
|--------|---------|-------------|
| `enable_app_gateway` | `true` | Application Gateway with WAF v2 |
| `enable_istio_service_mesh` | Scenario | Istio service mesh with mTLS |

### Storage

| Option | Default | Description |
|--------|---------|-------------|
| `enable_blob_csi_driver` | `true` | Azure Blob CSI driver |
| `enable_disk_csi_driver` | `true` | Azure Disk CSI driver |
| `enable_file_csi_driver` | `true` | Azure Files CSI driver |
| `enable_snapshot_controller` | `true` | Volume snapshot controller |

### GitOps & Extensions

| Option | Default | Description |
|--------|---------|-------------|
| `enable_flux` | Scenario | Flux v2 GitOps for declarative cluster management |
| `enable_dapr` | `false` | Dapr (Distributed Application Runtime) extension |

### Compliance

| Option | Default | Description |
|--------|---------|-------------|
| `enable_fips` | Scenario | FIPS 140-2 compliant node OS |
| `enable_backup` | Scenario | Azure Backup for AKS workloads |
| `enable_cost_analysis` | Scenario | Cost analysis add-on for reporting |

### Multi-Region

| Option | Default | Description |
|--------|---------|-------------|
| `secondary_location` | `""` | Secondary Azure region for geo-replication |
| `enable_acr_geo_replication` | Scenario | Geo-replicate ACR to secondary region |

---

## Subnet Architecture

Following the [AKS Baseline best practice](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks#plan-the-ip-addresses), system and user node pools are deployed to **separate subnets**:

```
VNet: 10.10.0.0/16
├── snet-aks-system-*   10.10.0.0/24   (256 IPs) — System node pool
├── snet-aks-user-*     10.10.1.0/22   (1024 IPs) — User node pool
├── snet-aks-apiserver-* 10.10.5.0/28  (16 IPs)  — API Server VNet Integration
├── snet-agw-*          10.10.6.0/24   (256 IPs) — Application Gateway
├── snet-pe-*           10.10.7.0/24   (256 IPs) — Private Endpoints
└── snet-ingress-*      10.10.8.0/24   (256 IPs) — Ingress LB
```

### Why separate subnets?

> *"Always separate the system node pool from the user node pool... This isolation results in more subnets that are smaller in size."*
> — [AKS Baseline Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)

Benefits:
- **Network isolation**: Apply different NSG rules to system vs. workload traffic
- **Independent sizing**: Size system subnet smaller (256 IPs) vs. user subnet larger (1024 IPs)
- **Route control**: Apply different UDR policies per pool if needed
- **Blast radius reduction**: Issues in user workloads don't saturate system pool IP space

Each subnet gets its own NSG:
- `nsg-aks-system-*` — System node pool NSG
- `nsg-aks-user-*` — User node pool NSG

Both subnets share the same route table for corp landing zones (UDR to hub firewall).

> **Note (topology):** The route table and the spoke↔hub VNet peerings are only created when `topology: spoke` or `topology: hub_and_spoke` (i.e. `hub_vnet_resource_id` is set). When `topology: standalone` is selected, no route table is created, no peering is attempted, and egress leaves the cluster through the spoke's NAT gateway instead. For `hub_and_spoke`, the cmdlet runs `bootstrap/alz/hub/` first — creating a new hub VNet plus an optional Azure Firewall (Standard or Premium SKU; Basic is intentionally not supported in v1.3 because it requires a Management subnet and Management IP) — and captures the hub outputs into the spoke render automatically.

### Standalone topology — security defaults & trade-offs

Standalone deployments have no hub for private connectivity, so AKS defaults are tuned for **dev/test reachability**, not production. Review and harden these for any production-bound standalone cluster:

| Setting | Standalone default | Production recommendation |
| --- | --- | --- |
| `private_cluster_enabled` | `false` (public API server) | `true` if you have VPN/Bastion/jumpbox; else lock down `api_server_authorized_ip_ranges` |
| `api_server_authorized_ip_ranges` | `[]` (open to internet) | **Always populate** with your corporate egress + CI runner CIDRs |
| `private_dns_zone_id` | `"system"` (Azure-managed) | `"system"` is fine for standalone; use a hub-owned zone for spoke topologies |
| `outbound_type` | `loadBalancer` (NAT gateway egress) | Acceptable; switch to `userDefinedRouting` if you add an egress firewall |
| `enable_api_server_vnet_integration` | `true` | Keep `true` — API server gets a private IP inside the spoke VNet |

**Why these defaults?** A truly-private cluster (no public FQDN, no public IP) is unreachable without an existing VPN/Bastion. Standalone is most often used for greenfield POCs where the deployer wants `kubectl` access immediately after apply. Production users should override these via `aks-landing-zone.<env>.tfvars` (or the wizard) before going live.

---

## Usage

Set the scenario in `config/inputs.yaml`:

```yaml
scenario: "single_region_regulated"
```

Then run:

```powershell
Deploy-AKSLandingZone -InputConfigPath .\config\inputs.yaml -AutoApprove
```

For a quick start, copy one of the pre-built scenario tfvars files:

```powershell
Copy-Item templates\scenarios\single_region_regulated.tfvars config\aks-landing-zone.tfvars
```

### Customizing options

Override any option in your `inputs.yaml` or `aks-landing-zone.tfvars`:

```yaml
# Use baseline scenario but add Istio
scenario: "single_region_baseline"
enable_istio: true
```

---

## Using azd

The repository ships an `azure.yaml` so the accelerator can be launched with
the [Azure Developer CLI](https://aka.ms/azd):

```powershell
azd up
```

**`azd up` is only a thin launcher.** The `preprovision` hook in `azure.yaml`
imports the `ALZ.AKS` module and runs the interactive `Deploy-AKSLandingZone`
wizard — exactly the same code path as calling the cmdlet directly. The
`infra/` folder is an intentional **no-op Terraform shim** (zero Azure
resources) that exists only so azd's provision step completes cleanly after
the wizard has finished.

### Why azd is not the primary provisioning model

The accelerator does not fit azd's declarative provision → deploy lifecycle:

- It is **interactive** — it prompts for topology, GitHub PATs, and
  per-environment values that azd's pipeline cannot supply declaratively.
- It provisions a **GitHub workload repository**, federated workload
  identities, and reusable workflow templates — none of which are Azure
  resources azd can model.
- It targets **multiple subscriptions** (bootstrap, AKS landing zone,
  connectivity) within a single run.
- It creates a **Terraform remote-state backend and then migrates its own
  state** into it — a bootstrap concern that sits outside any single
  `terraform apply`.
- The real workload infrastructure (`terraform/`) is applied by the generated
  workload repository's **CD pipeline**, not from the operator's machine.

For full control over actions (`apply`, `refresh`, `destroy`, `import`),
`-DryRun`, multi-environment loops, and `-AutoApprove`, invoke the module
directly:

```powershell
Import-Module ./ALZ.AKS/ALZ.AKS.psd1 -Force
Deploy-AKSLandingZone
```
