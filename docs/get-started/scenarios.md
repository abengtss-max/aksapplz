# Choose a scenario

The accelerator uses **scenarios** (pre-tuned blueprints) and **options** (individual feature
toggles). Pick a scenario as your starting point, then customize options as needed. This mirrors
the [Azure Landing Zones Accelerator](https://aka.ms/alz/acc/scenarios) pattern.

## Scenarios at a glance

| Scenario | SKU | Network policy | FIPS | Istio | Multi-region | Use case |
|---|---|---|---|---|---|---|
| `single_region_baseline` | Standard | Calico | No | No | No | Standard AKS baseline in one region |
| `multi_region_baseline` | Standard | Calico | No | No | Yes | Resilient baseline with Front Door + Fleet Manager |
| `single_region_regulated` | Premium | Azure | Yes | Yes | No | PCI-DSS 4.0.1 compliant, single region |
| `multi_region_regulated` | Premium | Azure | Yes | Yes | Yes | PCI-DSS 4.0.1 compliant, multi-region |

## Single-region baseline

The default. Deploys the
[AKS Baseline Reference Architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
in one region:

- Azure CNI Overlay + Calico network policy
- Workload Identity + Azure RBAC
- Defender for Containers
- KEDA autoscaling
- Managed Prometheus + Grafana
- Application Gateway WAF v2
- ACR (Premium, zone-redundant) + Key Vault
- System and user node pools on separate subnets

## Multi-region baseline

Everything in the baseline, plus a complete second region from a single run:

- Two full regional stacks from one reusable region module
- **Azure Front Door** (default) or **Traffic Manager** global load balancer with priority failover
- **Azure Kubernetes Fleet Manager** auto-joining both clusters
- **Geo-replicated ACR** across both regions
- **Flux v2 GitOps** and **VPA** for consistent, right-sized multi-cluster workloads
- **Azure Backup** for cross-region recovery

See **[Multi-region](../concepts/multi-region.md)** for the architecture and load-balancer choices.

## Regulated (PCI-DSS 4.0.1)

Hardened for [PCI-DSS](https://learn.microsoft.com/azure/aks/pci-network-segmentation):

- **Premium SKU** (required for regulated workloads)
- **Azure network policy** (PCI network segmentation)
- **Istio service mesh** with mTLS for data-in-transit encryption
- **FIPS 140-2** compliant node OS
- **Local accounts disabled** (Entra ID only)
- **Azure Backup** for data protection

!!! warning "Regulated scenarios are tech preview"
    The regulated blueprints are not yet in the GA validation matrix. See
    **[Known issues](../known-issues.md)** before using them in production.

## Customizing options

Any option can be overridden in `config/inputs.<env>.yaml` regardless of the scenario you chose —
for example toggling `enable_agc`, `enable_app_gateway`, `enable_vpa`, or the Kubernetes version.
See the **[Configuration reference](../reference/configuration.md)** for the full list.
