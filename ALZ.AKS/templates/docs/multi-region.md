# Multi-Region AKS Landing Zone

## What This Accelerator Deploys (Automated)

When you select a `multi_region_*` scenario, the accelerator automatically configures:

| Resource | Multi-Region Feature |
|---|---|
| **Azure Container Registry** | Geo-replicated to `secondary_location` (Premium SKU, zone-redundant) |
| **AKS Cluster** | Single-region primary cluster with all scenario defaults (Flux, VPA, Backup) |

## What Requires Manual Setup

The following multi-region components are **not automated** by this accelerator because they require organization-specific design decisions:

### 1. Second AKS Cluster (Secondary Region)

Run this accelerator a second time targeting the secondary subscription/region, or duplicate the Terraform configuration:

```bash
# Option A: Run the bootstrap again for region 2
Import-Module ./ALZ.AKS/ALZ.AKS.psd1
Deploy-AKSLandingZone
# Select the same scenario, but choose secondary_location as the primary location
```

### 2. Azure Kubernetes Fleet Manager

Fleet Manager orchestrates multi-cluster update sequencing and workload placement.

```bash
# Create Fleet Manager
az fleet create \
  --name fleet-aks-prod \
  --resource-group rg-fleet-prod \
  --location <primary-location>

# Join clusters
az fleet member create \
  --fleet-name fleet-aks-prod \
  --resource-group rg-fleet-prod \
  --name cluster-primary \
  --member-cluster-id <primary-aks-resource-id>

az fleet member create \
  --fleet-name fleet-aks-prod \
  --resource-group rg-fleet-prod \
  --name cluster-secondary \
  --member-cluster-id <secondary-aks-resource-id>
```

Reference: [Azure Kubernetes Fleet Manager](https://learn.microsoft.com/azure/kubernetes-fleet/overview)

### 3. Azure Front Door (Global Load Balancing)

Front Door provides global HTTP load balancing, SSL offloading, and failover across regions.

```bash
# Create Front Door profile
az afd profile create \
  --profile-name fd-aks-prod \
  --resource-group rg-frontdoor-prod \
  --sku Premium_AzureFrontDoor

# Add origins (one per region)
az afd origin-group create \
  --profile-name fd-aks-prod \
  --resource-group rg-frontdoor-prod \
  --origin-group-name og-aks \
  --probe-path /healthz \
  --probe-protocol Https

az afd origin create \
  --profile-name fd-aks-prod \
  --resource-group rg-frontdoor-prod \
  --origin-group-name og-aks \
  --origin-name primary \
  --host-name <primary-app-gateway-ip-or-fqdn> \
  --priority 1

az afd origin create \
  --profile-name fd-aks-prod \
  --resource-group rg-frontdoor-prod \
  --origin-group-name og-aks \
  --origin-name secondary \
  --host-name <secondary-app-gateway-ip-or-fqdn> \
  --priority 2
```

Reference: [Azure Front Door with AKS](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks-multi-region/aks-multi-cluster)

### 4. Cross-Region DNS

Configure Azure DNS or Traffic Manager for failover routing:

- **Active-Passive**: Use Front Door priority-based routing (shown above)
- **Active-Active**: Use Front Door weighted routing or latency-based routing

## Architecture Diagram

```
                    ┌──────────────┐
                    │ Azure Front  │
                    │    Door      │
                    └──────┬───────┘
                           │
              ┌────────────┴────────────┐
              │                         │
     ┌────────▼────────┐      ┌────────▼────────┐
     │  Primary Region │      │ Secondary Region│
     │  (automated)    │      │  (manual setup) │
     ├─────────────────┤      ├─────────────────┤
     │ AKS Cluster     │      │ AKS Cluster     │
     │ App Gateway     │      │ App Gateway     │
     │ Spoke VNet      │      │ Spoke VNet      │
     │ Key Vault       │      │ Key Vault       │
     └────────┬────────┘      └────────┬────────┘
              │                         │
              └────────────┬────────────┘
                           │
                  ┌────────▼────────┐
                  │  Shared Infra   │
                  ├─────────────────┤
                  │ ACR (geo-repl.) │
                  │ Fleet Manager   │
                  │ Log Analytics   │
                  └─────────────────┘
```

## Configuration Variables

| Variable | Description | Default |
|---|---|---|
| `secondary_location` | Azure region for geo-replication | `""` (disabled) |
| `enable_acr_geo_replication` | Enable ACR geo-replication to secondary region | `false` (`true` for multi-region scenarios) |

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
