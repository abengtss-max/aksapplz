# Multi-Region AKS Landing Zone

## What This Accelerator Deploys (Automated)

When you select a `multi_region_*` scenario and set `secondary_location`, the
accelerator provisions a **complete second region** plus an opt-in global load
balancer — all from a single deployment, using Azure Verified Modules (AVM).

| Resource | Multi-Region Behavior |
|---|---|
| **Region module** | The whole regional stack (AKS + App Gateway + spoke VNet + Key Vault + Log Analytics + monitoring) is a reusable module instantiated once per region via `for_each`. Primary is always deployed; secondary is added when `secondary_location` is set. |
| **AKS Cluster** | A fully-configured cluster in **each** region with identical scenario defaults (add-ons, node pools, identity, RBAC). |
| **Application Gateway** | One per region, fronting that region's cluster. |
| **Spoke VNet + subnets + NSGs** | One per region (secondary uses `secondary_vnet_address_space` / `secondary_subnet_address_prefixes`). |
| **Key Vault** | One per region. |
| **Azure Container Registry** | A single registry **geo-replicated** to `secondary_location` (Premium, zone-redundant). |
| **Global load balancer** | Opt-in via `global_lb_type`: **Azure Front Door Premium** or **Azure Traffic Manager**. Both regions' App Gateways are wired in as origins/endpoints automatically. |
| **Azure Kubernetes Fleet Manager** | Opt-in via `enable_fleet_manager`; both clusters are auto-joined as members. |

There is **no manual second pass** — one `Deploy-AKSLandingZone` run (or one
`terraform apply`) stands up both regions and the chosen global LB.

## Choosing a Global Load Balancer

`global_lb_type` is mutually exclusive — pick the one that fits your traffic model:

| Value | Service | Use when |
|---|---|---|
| `front_door` | Azure Front Door Premium | You want anycast HTTP/S, WAF, TLS offload, and fast (sub-minute) failover at the edge. **Default** for multi-region scenarios. |
| `traffic_manager` | Azure Traffic Manager | You want DNS-based priority/weighted/performance routing (works for any protocol, not just HTTP). |
| `none` | (no global LB) | You manage cross-region DNS/routing yourself. |

Both options use **priority routing** by default (primary active, secondary on
standby) with health probes against each region's App Gateway public endpoint.
The module gates the global LB on `enable_app_gateway` (an App Gateway origin is
required), and uses static region keys so the plan is fully known before apply.

References:
- [AKS multi-region / multi-cluster reference architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster)
- [Azure Front Door](https://learn.microsoft.com/azure/frontdoor/front-door-overview)
- [Azure Traffic Manager](https://learn.microsoft.com/azure/traffic-manager/traffic-manager-overview)
- [Azure Kubernetes Fleet Manager](https://learn.microsoft.com/azure/kubernetes-fleet/overview)

## Availability Zones per Region

AKS node-pool zone support **varies by region and VM SKU** — some regions expose
only a subset of zones for a given size (for example, a region may offer only
zone `3`). Requesting an unsupported zone fails with
`AvailabilityZoneNotSupported`.

- `availability_zones` applies to the **primary** region.
- `secondary_availability_zones` applies to the **secondary** region. Leave it
  empty (`[]`) to inherit the primary's zones, or set it explicitly when the
  secondary region/SKU supports a different set.

```hcl
availability_zones           = ["1", "2", "3"]  # primary
secondary_availability_zones = ["3"]            # secondary only supports zone 3
```

The interactive wizard prompts for the secondary region's zones during a
multi-region run; press Enter to inherit the primary's.

## Architecture Diagram

```
              ┌───────────────────────────────┐
              │  Global LB (opt-in)            │
              │  Front Door  OR  Traffic Mgr   │
              └───────────────┬───────────────┘
                              │ priority routing + health probes
              ┌───────────────┴───────────────┐
              │                                │
     ┌────────▼────────┐            ┌─────────▼────────┐
     │  Primary Region │            │ Secondary Region │
     │  (automated)    │            │  (automated)     │
     ├─────────────────┤            ├──────────────────┤
     │ App Gateway     │            │ App Gateway      │
     │ AKS Cluster     │            │ AKS Cluster      │
     │ Spoke VNet      │            │ Spoke VNet       │
     │ Key Vault       │            │ Key Vault        │
     │ Log Analytics   │            │ Log Analytics    │
     └────────┬────────┘            └─────────┬────────┘
              │                                │
              └───────────────┬───────────────┘
                              │
                  ┌───────────▼───────────┐
                  │  Shared Infra          │
                  ├────────────────────────┤
                  │ ACR (geo-replicated)   │
                  │ Fleet Manager (opt-in) │
                  └────────────────────────┘
```

## Configuration Variables

| Variable | Description | Default |
|---|---|---|
| `secondary_location` | Azure region for the secondary stack (enables multi-region) | `""` (disabled) |
| `global_lb_type` | Global load balancer: `none` \| `front_door` \| `traffic_manager` | `front_door` (multi-region scenarios) |
| `enable_fleet_manager` | Auto-join both clusters into an Azure Kubernetes Fleet Manager | `true` (multi-region scenarios) |
| `enable_acr_geo_replication` | Geo-replicate ACR to the secondary region | `false` (`true` for multi-region scenarios) |
| `secondary_vnet_address_space` | Secondary spoke VNet CIDR (must not overlap primary) | `"10.20.0.0/16"` |
| `secondary_subnet_address_prefixes` | Per-subnet CIDRs for the secondary region | see scenario tfvars |
| `secondary_availability_zones` | AKS node-pool zones for the secondary region; `[]` inherits primary | `[]` |

## Outputs

Multi-region deployments expose both backward-compatible primary scalars and
per-region maps / global endpoints:

| Output | Description |
|---|---|
| `regions` | List of deployed region keys (`primary`, `secondary`) |
| `aks_cluster_names` / `aks_cluster_ids` | Map of region key → cluster |
| `app_gateway_public_ips` | Map of region key → App Gateway public IP |
| `global_lb_type` | Active global LB type |
| `front_door_endpoint_hostname` | Front Door hostname (when `front_door`) |
| `traffic_manager_fqdn` | Traffic Manager FQDN (when `traffic_manager`) |
| `fleet_manager_id` | Fleet Manager ID (when enabled) |

## Flux GitOps for Multi-Cluster

Multi-region scenarios enable Flux by default. This ensures consistent application deployment across clusters:

1. Both clusters point to the same Git repository
2. Flux reconciles desired state in each cluster independently
3. Use Kustomize overlays for region-specific configuration

```yaml
# Example: kustomization.yaml per region
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
patches:
  - path: region-patch.yaml
```
