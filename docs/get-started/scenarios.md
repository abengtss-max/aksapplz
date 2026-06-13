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

<p align="center"><img src="../../assets/arch-baseline.png" alt="Single-region baseline architecture: a hub virtual network with Azure Bastion, Azure Firewall, and a gateway subnet to on-premises, peered to a spoke virtual network containing subnets for Private Link endpoints, API server VNet integration, ingress resources, and the Application Gateway. The cluster nodes subnet holds the private AKS cluster with separate system (CoreDNS, metric-server) and user (workload) node pools. Key Vault and Container Registry connect over Private Link; Azure Monitor workspace collects metrics and Managed Prometheus." width="900" style="background:#ffffff;border-radius:16px;padding:16px;box-shadow:0 2px 12px rgba(0,0,0,0.08)"></p>

## Multi-region baseline

Everything in the baseline, plus a complete second region from a single run:

- Two full regional stacks from one reusable region module
- **Azure Front Door** (default) or **Traffic Manager** global load balancer with priority failover
- **Azure Kubernetes Fleet Manager** auto-joining both clusters
- **Geo-replicated ACR** across both regions
- **Flux v2 GitOps** and **VPA** for consistent, right-sized multi-cluster workloads
- **Azure Backup** for cross-region recovery

<p align="center"><img src="../../assets/arch-multi-region.png" alt="Multi-region baseline architecture: two regions (A and B), each with a regional hub network (Azure Bastion, Azure Firewall) peered to a spoke virtual network running Kubernetes services, an internal load balancer, and Application Gateway, plus a regional Key Vault, Container Registry replica, and Log Analytics. A shared-resources column holds the source Container Registry, Azure Front Door as the global load balancer, Azure Kubernetes Fleet Manager, and Log Analytics. A Microsoft-managed Fleet hub cluster coordinates both regional clusters." width="960" style="background:#ffffff;border-radius:16px;padding:16px;box-shadow:0 2px 12px rgba(0,0,0,0.08)"></p>

See **[Multi-region](../concepts/multi-region.md)** for the architecture and load-balancer choices.

## Regulated (PCI-DSS 4.0.1)

Hardened for [PCI-DSS](https://learn.microsoft.com/azure/aks/pci-network-segmentation), aligned with
the Microsoft Learn [AKS regulated cluster reference architecture](https://learn.microsoft.com/azure/aks/pci-ra-code-assets):

- **Premium SKU** (required for regulated workloads)
- **Private cluster** with API server VNet integration (Entra ID only, local accounts disabled)
- **Application Gateway WAF** for inbound, **Azure Firewall** (hub) for egress
- **Azure network policy** (PCI network segmentation)
- **Istio service mesh** with mTLS for data-in-transit encryption between pods
- **FIPS 140-2** compliant node OS on system and user node pools
- **Microsoft Defender for Containers** + **Azure Policy** guardrails
- **Azure Monitor + Log Analytics** (90-day retention) and Managed Prometheus
- **Azure Backup** for data protection
- **Key Vault** and **Container Registry** reachable over **Private Link**

<p align="center"><img src="../../assets/arch-regulated.png" alt="Single-region regulated PCI-DSS 4.0.1 architecture as deployed: a hub virtual network with an Azure Firewall subnet (outbound egress) peered via VNet peering to on-premises and other spokes, and to a spoke virtual network. The spoke contains an API server VNet integration subnet (Entra ID only), an internal load balancer subnet, an Application Gateway with WAF subnet receiving internet traffic, a private endpoints subnet, and a private cluster nodes subnet with a private AKS cluster running FIPS 140-2 system and user node pools and pods secured by an Istio service mesh with mTLS. Key Vault, Container Registry, and the AKS API server are reachable over Private Link. Platform services include Microsoft Defender for Containers, Azure Policy, Azure Monitor with Log Analytics 90-day retention, and an Azure Backup vault." width="960" style="background:#ffffff;border-radius:16px;padding:16px;box-shadow:0 2px 12px rgba(0,0,0,0.08)"></p>

!!! info "Reference alignment & deltas"
    This blueprint maps to the Microsoft Learn regulated reference on the security-critical
    controls (private cluster, WAF, mTLS, FIPS, Defender, Azure Policy, Entra-ID-only access,
    90-day logs, backup, dedicated subnets). The reference also describes
    *defense-in-depth* elements the accelerator does **not** yet deploy — a second user node
    pool for in-scope/out-of-scope segmentation, host-based encryption, customer-managed keys
    (BYOK), DDoS Network Protection, and an SRE jump-box / image-build spoke. These are tracked
    in [GAPS.md](https://github.com/abengtss-max/aksapplz/blob/main/GAPS.md) (section G).

!!! warning "Regulated scenarios are tech preview"
    The regulated blueprints are not yet in the GA validation matrix, and the Microsoft reference
    itself is not certified — deploying it does **not** clear a PCI-DSS audit. Always engage a
    Qualified Security Assessor (QSA). See **[Known issues](../known-issues.md)** before using
    these in production.

## Customizing options

Any option can be overridden in `config/inputs.<env>.yaml` regardless of the scenario you chose —
for example toggling `enable_agc`, `enable_app_gateway`, `enable_vpa`, or the Kubernetes version.
See the **[Configuration reference](../reference/configuration.md)** for the full list.
