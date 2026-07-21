# Topologies

The accelerator supports three networking topologies. The wizard asks which one you want — this
page explains the trade-offs.

<p align="center">
  <img src="../../assets/topologies.png" alt="AKS Landing Zone Accelerator topology options. A decision header routes you to the right model: have an existing Azure Landing Zone? Choose Option 1; need a secure platform foundation? Choose Option 2; need a quick, isolated deployment? Choose Option 3. Option 1 — Existing Hub Integration: deploy AKS into an existing ALZ hub-and-spoke network; the private AKS spoke VNet peers to a hub that already provides Azure Firewall, Azure Bastion, DNS/Private DNS, and VPN/ExpressRoute; best for customers with an existing ALZ; key difference is it reuses the existing hub and shared network services. Option 2 — New Hub-and-Spoke: the accelerator creates a new secured hub VNet with Azure Firewall, DNS, Bastion, and connectivity, peered to an AKS spoke VNet with a private cluster, and traffic egresses to Internet/on-prem through the hub; best for customers building a secure enterprise foundation; key difference is it creates a new hub with centralized network and security services. Option 3 — Standalone AKS: deploy AKS with direct outbound internet access via a NAT gateway, no hub; best for pilots, labs, or isolated environments; key difference is no hub and direct outbound connectivity. Recommendation: for production workloads use Option 1 or Option 2 to ensure security, governance, and connectivity consistency." width="900"
       style="background:#ffffff;border-radius:16px;padding:16px;box-shadow:0 6px 24px rgba(0,0,0,.15);">
</p>

| Option | Topology | What it creates | Best for | Status |
|---|---|---|---|---|
| **Option 1** | `spoke` | The AKS spoke peered to an **existing** hub VNet you already own | Brownfield: you already have an ALZ hub | ⚠️ Available, not in current validation matrix |
| **Option 2** | `hub_and_spoke` | A **new** hub VNet + Azure Firewall + the spoke peered to it | Greenfield enterprise | ✅ GA (single region) |
| **Option 3** | `standalone` | AKS spoke + NAT gateway egress, no hub | Dev/test, PoCs, isolated subscriptions | ✅ GA (single + multi-region) |

## Option 1 — spoke

Peer the AKS spoke into a hub VNet you already manage (a typical brownfield ALZ). You supply the
existing hub VNet resource ID during the wizard.

## Option 2 — hub_and_spoke

The accelerator provisions a brand-new hub VNet with **Azure Firewall** plus the AKS spoke peered
to it. Choose this for greenfield enterprise deployments where the accelerator owns the whole
network. You provide the hub address space and firewall SKU during the wizard.

!!! note "Cost"
    Azure Firewall (Standard) runs continuously. Tear the environment down when you're done
    evaluating to avoid ongoing charges.

## Option 3 — standalone

No hub. Egress is via a NAT gateway. This is the fastest path and the recommended choice for a
first run. Ideal when the subscription is isolated and you don't need centralized inspection.

## Ingress options

Topology controls egress and peering; ingress is a separate set of toggles that coexist:

| Toggle | Purpose |
|---|---|
| `enable_app_gateway` | Application Gateway WAF v2 — L7 ingress with a Web Application Firewall |
| `enable_agc` | Application Gateway for Containers (ALB) — provisions the delegated subnet + NSG; the in-cluster ALB Controller manages the data plane |

Both are regional. For global traffic distribution across regions, see
**[Multi-region](multi-region.md)**.
